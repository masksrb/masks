import { organizationKey } from "../claims.js";
import { type Client, scopes as scopesOf, type Token } from "../client.js";
import { DELEGATION_SCOPE } from "../delegations.js";
import { MasksError } from "../errors.js";
import { Handshake } from "../handshake.js";
import type { IdTokenClaims, LogoutToken } from "../idtoken.js";
import { RESOURCE_PATH } from "../issuer.js";
import { Verifier } from "../verifier.js";
import { type CredentialStore, defaultCredentials } from "./credentials.js";
import { IssuerCache } from "./issuers.js";
import { Masked } from "./masked.js";
import {
  approvedScope,
  type PrivilegeSpec,
  Privileges,
  unique,
} from "./privileges.js";
import { renew } from "./refresh.js";
import { localPath, type PerRequest, resolve } from "./requests.js";
import { Sealer } from "./seal.js";
import {
  fresh,
  type HeldTokens,
  held,
  pick,
  type SessionData,
  Sessions,
  Visit,
} from "./session.js";
import {
  memoryStore,
  processEnv,
  remember,
  replayStore,
  type Store,
  shared,
} from "./stores.js";

export interface MasksOptions {
  env?: Record<string, string | undefined>;
  issuer?: PerRequest<string>;
  resource?: PerRequest<string>;
  name?: PerRequest<string>;
  organization?: PerRequest<string | undefined>;
  scope?: string[];
  namespace?: string;
  resourceScopes?: string[];
  privileges?: Record<string, PrivilegeSpec>;
  basePath?: string;
  afterSignIn?: string;
  afterSignOut?: string;
  signOutOfIssuer?: boolean;
  secret?: string | string[];
  maxAge?: number;
  sessions?: Store;
  store?: Store;
  credentials?: CredentialStore;
  manages?:
    | string
    | ((request: Request, masked: Masked) => boolean | Promise<boolean>);
  delegations?: string;
  onLogout?: (logout: LogoutToken, request: Request) => void | Promise<void>;
  avatarBytes?: number;
  fetch?: typeof fetch;
  allowPlainHTTP?: boolean;
}

export const DEFAULT_SCOPE = ["openid", "profile", "email", "offline_access"];

const REMEMBERED_VERIFIERS = 1_000;
const REMEMBERED_REGISTRATIONS = 1_000;
const REGISTRATION_TRUSTED = 60_000;

export class Core {
  readonly options: MasksOptions;
  readonly privileges: Privileges;
  readonly basePath: string;
  readonly scope: string[];
  readonly maxAge: number;
  readonly credentials: CredentialStore;
  readonly store: Store;
  readonly sessions: Sessions;
  readonly issuers = new IssuerCache(() => ({
    fetch: this.options.fetch,
    allowPlainHTTP: this.options.allowPlainHTTP,
  }));
  readonly #verifiers = new Map<string, Verifier>();
  readonly #registeredAt = new Map<string, number>();
  readonly #visits = new WeakMap<Request, Promise<Visit>>();

  #sealer?: Sealer;

  constructor(options: MasksOptions) {
    this.options = options;
    this.privileges = new Privileges(options.privileges);
    this.basePath = `/${(options.basePath ?? "/auth").replace(/^\/+|\/+$/g, "")}`;
    this.scope = options.scope ?? DEFAULT_SCOPE;
    this.maxAge = options.maxAge ?? 14 * 24 * 3600;
    this.credentials =
      options.credentials ?? defaultCredentials(this.env, "MASKS_CLIENT");
    this.store = options.store ?? shared("store", () => memoryStore());
    this.sessions = new Sessions({
      seal: () => this.seal,
      sessions: options.sessions,
      store: this.store,
      maxAge: this.maxAge,
    });

    if (options.secret !== undefined) this.#sealer = new Sealer(options.secret);
  }

  get env(): Record<string, string | undefined> {
    return this.options.env ?? processEnv();
  }

  get seal(): Sealer {
    this.#sealer ??= new Sealer(
      (this.env.MASKS_SECRET ?? "").split(",").map((part) => part.trim()),
    );

    return this.#sealer;
  }

  get logoutPath(): string {
    return `${this.basePath}/logout`;
  }

  get handshakePath(): string {
    return `${this.basePath}/handshake`;
  }

  loginURL(
    asked: {
      returnTo?: string;
      organization?: string;
      privilege?: string | string[];
    } = {},
  ): string {
    const query = new URLSearchParams();
    const returnTo = localPath(asked.returnTo);
    const organization = organizationKey(asked.organization);
    const privileges = [asked.privilege ?? []].flat();

    for (const name of privileges) this.privileges.get(name);

    if (returnTo) query.set("return_to", returnTo);
    if (organization) query.set("organization", organization);
    if (privileges.length > 0) query.set("privilege", privileges.join(" "));

    const held = query.toString();

    return held ? `${this.basePath}?${held}` : this.basePath;
  }

  owns(pathname: string): boolean {
    return (
      pathname === this.basePath ||
      pathname.startsWith(`${this.basePath}/`) ||
      pathname.startsWith(RESOURCE_PATH)
    );
  }

  returnTo(asked: string | null | undefined): string | undefined {
    const path = localPath(asked);

    if (!path) return undefined;

    const { pathname } = new URL(path, "http://app");

    if (this.owns(pathname) && pathname !== this.handshakePath)
      return undefined;

    return path;
  }

  handshakeURL(returnTo: string | undefined): string {
    const path = this.returnTo(returnTo);

    if (!path) return this.handshakePath;

    return `${this.handshakePath}?${new URLSearchParams({ return_to: path })}`;
  }

  visit(request: Request): Promise<Visit> {
    let held = this.#visits.get(request);

    if (!held) {
      held = this.#newVisit(request);
      this.#visits.set(request, held);
    }

    return held;
  }

  async current(visit: Visit): Promise<SessionData | undefined> {
    const session = await this.sessions.read(visit);
    const data = session?.data;
    const refreshToken = data?.tokens?.refresh_token;

    if (!data?.tokens || fresh(data.tokens) || !refreshToken) return data;

    const client = await this.client(visit);
    if (!client) return data;

    const renewal = await renew({
      store: this.store,
      issuer: visit.issuerURL,
      refreshToken,
      refresh: () => this.#refresh(visit, client, refreshToken, data.identity),
      expiresAt: (renewed) => renewed.tokens.expires_at,
    });

    switch (renewal.outcome) {
      case "renewed": {
        const renewed = { ...data, ...renewal.value };

        await this.sessions.write(visit, renewed, false);

        return renewed;
      }
      case "unregistered":
        await this.disconnect(visit.request);
        await this.sessions.forget(visit);

        return undefined;
      case "refused":
        await this.sessions.forget(visit);

        return undefined;
      default:
        return data;
    }
  }

  masked(visit: Visit, data: SessionData | undefined): Masked {
    const tokens = data?.tokens;

    if (!tokens) return Masked.nobody(this.privileges);

    return new Masked({
      claims: data.identity,
      scopes: scopesOf(tokens),
      signedIn: fresh(tokens),
      privileges: this.privileges,
      accessToken: tokens.access_token,
      tokenType: tokens.token_type,
      expiresAt: tokens.expires_at,
      accountURL: visit.issuerURL ? `${visit.issuerURL}/` : undefined,
      avatarURL: `${this.basePath}/avatar`,
    });
  }

  async identity(
    client: Client,
    token: Token,
    claims: IdTokenClaims | undefined,
  ): Promise<Record<string, unknown>> {
    let profile: Record<string, unknown> = {};

    try {
      const found = await client.userinfo(token);

      if (!claims || found.sub === claims.sub) profile = found;
    } catch {}

    return pick({ ...profile, ...(claims ?? {}) });
  }

  async client(visit: Visit): Promise<Client | undefined> {
    const held = await this.credentials.read(visit.request);

    if (!held?.client_id) return undefined;

    return (await this.issuers.get(visit.issuerURL)).client(held);
  }

  async configured(visit: Visit): Promise<boolean> {
    return !!(await this.credentials.read(visit.request))?.client_id;
  }

  async registered(request: Request): Promise<boolean> {
    const visit = await this.visit(request);
    const held = await this.credentials.read(request);

    if (!held?.registration_client_uri || !held.registration_access_token)
      return true;

    try {
      await (await this.issuers.get(visit.issuerURL)).readRegistration(held);
      return true;
    } catch (error) {
      return !(
        error instanceof MasksError &&
        [401, 403, 404].includes(error.status ?? 0)
      );
    }
  }

  async stillRegistered(visit: Visit, clientID: string): Promise<boolean> {
    const key = `${visit.issuerURL} ${clientID}`;

    if ((this.#registeredAt.get(key) ?? 0) > Date.now() - REGISTRATION_TRUSTED)
      return true;

    const known = await this.registered(visit.request);

    if (known)
      remember(this.#registeredAt, key, Date.now(), REMEMBERED_REGISTRATIONS);
    else this.#registeredAt.delete(key);

    return known;
  }

  async disconnect(request: Request): Promise<boolean> {
    if (!this.credentials.clear) return false;

    const visit = await this.visit(request);
    const held = await this.credentials.read(request);

    if (held?.registration_client_uri && held.registration_access_token) {
      try {
        await (await this.issuers.get(visit.issuerURL)).deleteRegistration(
          held,
        );
      } catch {}
    }

    await this.credentials.clear(request);

    return true;
  }

  async verifier(visit: Visit): Promise<Verifier> {
    const key = `${visit.issuerURL} ${visit.resource}`;
    const issuer = await this.issuers.get(visit.issuerURL);
    const held = this.#verifiers.get(key);

    if (held?.issuer === issuer) return held;

    const made = new Verifier(issuer, visit.resource, {
      publicURL: visit.origin,
      replay: replayStore(this.store),
      resourceMetadata: this.metadataURL(visit),
    });

    remember(this.#verifiers, key, made, REMEMBERED_VERIFIERS);

    return made;
  }

  async handshake(visit: Visit): Promise<Handshake> {
    const issuer = await this.issuers.get(visit.issuerURL);
    const redirectURIs = [this.redirectURI(visit)];
    const delegation = this.delegationReturn(visit);

    if (delegation) redirectURIs.push(delegation);

    return new Handshake(issuer, {
      name:
        (await resolve(this.options.name, visit.request)) || "An application",
      resource: visit.resource,
      redirectURIs: unique(redirectURIs),
      returnTo: `${visit.origin}${this.basePath}/handshake/callback`,
      scope: approvedScope(
        this.scope,
        this.privileges,
        this.options.namespace,
        delegation ? [DELEGATION_SCOPE] : [],
      ),
      backchannelLogoutURI: `${visit.origin}${this.basePath}/logout/backchannel`,
      postLogoutRedirectUri: this.logoutReturn(visit),
    });
  }

  metadataPath(visit: Visit): string {
    const path = new URL(visit.resource).pathname.replace(/\/+$/, "");

    return `${RESOURCE_PATH}${path}`;
  }

  metadataURL(visit: Visit): string {
    return `${visit.origin}${this.metadataPath(visit)}`;
  }

  redirectURI(visit: Visit): string {
    return `${visit.origin}${this.basePath}/callback`;
  }

  logoutReturn(visit: Visit): string {
    return `${visit.origin}${this.basePath}/logout/return`;
  }

  delegationReturn(visit: Visit): string | undefined {
    const path = this.options.delegations;

    return path ? `${visit.origin}${localPath(path) ?? "/"}` : undefined;
  }

  async #newVisit(request: Request): Promise<Visit> {
    const visit = new Visit(request);
    const issuer =
      (await resolve(this.options.issuer, request)) ?? this.env.MASKS_ISSUER;
    const resource =
      (await resolve(this.options.resource, request)) ??
      this.env.MASKS_RESOURCE;

    if (!issuer)
      throw new Error(
        "masks: set MASKS_ISSUER, or pass issuer, to name the masks server",
      );
    if (!resource) {
      throw new Error(
        "masks: set MASKS_RESOURCE, or pass resource, to name this app by its absolute URL",
      );
    }

    let parsed: URL;

    try {
      parsed = new URL(resource);
    } catch {
      throw new Error(
        "masks: resource is this app's absolute URL, such as https://app.example.com",
      );
    }

    visit.issuerURL = issuer.replace(/\/+$/, "");
    visit.resource = resource;
    visit.origin = parsed.origin;
    visit.secure = parsed.protocol === "https:";

    return visit;
  }

  async #refresh(
    visit: Visit,
    client: Client,
    refreshToken: string,
    identity: Record<string, unknown> | undefined,
  ): Promise<{ tokens: HeldTokens; identity?: Record<string, unknown> }> {
    const renewed = await client.refresh(refreshToken, {
      resource: [visit.resource],
    });

    renewed.refresh_token ??= refreshToken;

    let kept = identity;

    try {
      const profile = await client.userinfo(renewed);

      if (!kept?.sub || profile.sub === kept.sub) {
        kept = pick({ ...(kept ?? {}), ...profile });
      }
    } catch {}

    return { tokens: held(renewed), identity: kept };
  }
}
