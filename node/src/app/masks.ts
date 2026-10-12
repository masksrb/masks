import { ForbiddenError, organizationKey } from "../claims.js";
import {
  Client,
  constantEqual,
  scopes as scopesOf,
  type Token,
} from "../client.js";
import {
  DELEGATION_SCOPE,
  type Connection as DelegatedConnection,
  DelegationRefused,
  Delegations,
} from "../delegations.js";
import { InvalidTokenError, MasksError, UnavailableError } from "../errors.js";
import { Handshake } from "../handshake.js";
import type { IdTokenClaims, LogoutToken } from "../idtoken.js";
import { Issuer, RESOURCE_PATH } from "../issuer.js";
import { random } from "../key.js";
import type { Registration } from "../registration.js";
import type { ReplayStore } from "../replay.js";
import { type Claims, Verifier } from "../verifier.js";
import { type AvatarsLimit, avatarResponse } from "./avatar.js";
import { parseCookies, readChunked, writeChunked } from "./cookies.js";
import { Masked } from "./masked.js";
import { type PrivilegeSpec, Privileges, unique } from "./privileges.js";
import { Sealer } from "./seal.js";
import {
  type CredentialStore,
  type Credentials,
  envCredentials,
  fileCredentials,
  type LogoutStore,
  memoryLogouts,
  processEnv,
  type SessionStore,
} from "./stores.js";

type PerRequest<T> = T | ((request: Request) => T | Promise<T>);

export interface MasksOptions {
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
  sessions?: SessionStore;
  credentials?: CredentialStore;
  logouts?: LogoutStore;
  replay?: ReplayStore;
  manages?:
    | string
    | ((request: Request, masked: Masked) => boolean | Promise<boolean>);
  delegations?: string;
  onLogout?: (logout: LogoutToken, request: Request) => void | Promise<void>;
  avatars?: AvatarsLimit;
  fetch?: typeof fetch;
  allowPlainHTTP?: boolean;
}

export interface HeldTokens {
  access_token: string;
  token_type: string;
  refresh_token?: string;
  scope: string;
  expires_at?: number;
}

export interface SessionData {
  tokens?: HeldTokens;
  identity?: Record<string, unknown>;
  signedInAt?: number;
  expiresAt?: number;
}

interface Pending {
  verifier: string;
  nonce?: string;
  returnTo?: string;
  redirectURI: string;
  resource?: string[];
  until: number;
}

interface DelegationPending {
  verifier: string;
  nonce?: string;
  provider: string;
  redirectURI: string;
  account: string;
  until: number;
}

interface FlowData {
  requests?: Record<string, Pending>;
  handshakes?: Record<string, { until: number }>;
  logouts?: Record<string, { until: number }>;
  delegations?: Record<string, DelegationPending>;
  steppedUp?: { privileges: string[]; at: number };
  restartedAt?: number;
}

export type Outcome =
  | {
      masked: Masked;
      cookies: string[];
      response?: undefined;
      error?: undefined;
    }
  | {
      masked?: undefined;
      cookies?: undefined;
      response: Response;
      error?: ForbiddenError;
    };

export interface Connection {
  connected: boolean;
  client_id?: string;
  issuer?: string;
}

export const DEFAULT_SCOPE = ["openid", "profile", "email", "offline_access"];

const IDENTITY = [
  "sub",
  "sid",
  "name",
  "preferred_username",
  "email",
  "email_verified",
  "tenant",
  "picture",
  "masks:avatars",
  "org",
  "orgs",
];
const FLOW_LIFETIME = 3600;
const FLOW_LIMIT = 5;
const STEP_UP_WITHIN = 300;
const RESTART_WITHIN = 60;
const REFRESH_LEEWAY = 30;
const REMEMBER_REFRESH = 60_000;
const DISCOVERY_LIFETIME = 3600_000;
const SESSION_PURPOSE = "session";
const FLOW_PURPOSE = "flow";

class Visit {
  readonly request: Request;
  readonly url: URL;
  readonly cookies: Map<string, string>;
  readonly out: string[] = [];
  origin = "";
  resource = "";
  secure = false;
  issuerURL = "";
  session?: { id?: string; data: SessionData } | null;
  flow?: FlowData;
  flowChanged = false;

  constructor(request: Request) {
    this.request = request;
    this.url = new URL(request.url);
    this.cookies = parseCookies(request.headers.get("cookie"));
  }
}

export class Masks {
  readonly privileges: Privileges;
  readonly basePath: string;
  readonly scope: string[];
  readonly maxAge: number;
  readonly #options: MasksOptions;
  readonly #credentials: CredentialStore;
  readonly #logouts: LogoutStore;
  readonly #issuers = new Map<
    string,
    { at: number; issuer: Promise<Issuer> }
  >();
  readonly #refreshing = new Map<string, Promise<SessionData | undefined>>();
  readonly #verifiers = new Map<string, Verifier>();
  #sealer?: Sealer;

  constructor(options: MasksOptions = {}) {
    this.#options = options;
    this.privileges = new Privileges(options.privileges);
    this.basePath = `/${(options.basePath ?? "/auth").replace(/^\/+|\/+$/g, "")}`;
    this.scope = options.scope ?? DEFAULT_SCOPE;
    this.maxAge = options.maxAge ?? 14 * 24 * 3600;
    this.#credentials =
      options.credentials ??
      (processEnv().MASKS_CLIENT_ID ? envCredentials() : fileCredentials());
    this.#logouts = options.logouts ?? memoryLogouts();

    if (options.secret !== undefined) this.#sealer = new Sealer(options.secret);
  }

  get #seal(): Sealer {
    this.#sealer ??= new Sealer(
      (processEnv().MASKS_SECRET ?? "").split(",").map((part) => part.trim()),
    );

    return this.#sealer;
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

  get logoutPath(): string {
    return `${this.basePath}/logout`;
  }

  get handshakePath(): string {
    return `${this.basePath}/handshake`;
  }

  async handle(request: Request): Promise<Response | undefined> {
    const visit = await this.#visit(request);
    const path = visit.url.pathname;

    if (request.method === "GET" && path === this.#metadataPath(visit)) {
      return json(200, await this.metadata(request), [], {
        "cache-control": "public, max-age=300",
      });
    }

    if (path !== this.basePath && !path.startsWith(`${this.basePath}/`)) {
      return undefined;
    }

    const route = path.slice(this.basePath.length).replace(/\/+$/, "") || "/";
    const method = request.method.toUpperCase();

    try {
      switch (`${method} ${route}`) {
        case "GET /":
          return await this.#start(visit);
        case "GET /callback":
          return await this.#callback(visit);
        case "GET /refresh":
          return await this.#refreshRoute(visit);
        case "GET /session":
          return await this.#sessionRoute(visit);
        case "GET /avatar":
          return await this.#avatar(visit);
        case "GET /logout":
        case "POST /logout":
        case "DELETE /logout":
          return await this.#logout(visit);
        case "POST /logout/backchannel":
          return await this.#backchannel(visit);
        case "GET /handshake":
          return await this.#handshakeShow(visit);
        case "POST /handshake":
          return await this.#handshakeCreate(visit);
        case "DELETE /handshake":
        case "POST /handshake/disconnect":
          return await this.#handshakeDestroy(visit);
        case "GET /handshake/callback":
          return await this.#handshakeCallback(visit);
        default:
          return text(404, "not found", visit.out);
      }
    } catch (error) {
      if (error instanceof MasksError) {
        return answer(visit, 400, error.code, error.description ?? error.code);
      }

      if (error instanceof UnavailableError || isNetwork(error)) {
        return answer(
          visit,
          503,
          "temporarily_unavailable",
          "masks could not be reached",
        );
      }

      throw error;
    }
  }

  async peek(request: Request): Promise<Masked> {
    const visit = await this.#visit(request);
    const session = await this.#readSession(visit);

    return this.#masked(visit, session?.data);
  }

  async masked(
    request: Request,
  ): Promise<{ masked: Masked; cookies: string[] }> {
    const visit = await this.#visit(request);
    const data = await this.#current(visit);

    return { masked: this.#masked(visit, data), cookies: visit.out };
  }

  require(request: Request, ...names: string[]): Promise<Outcome> {
    return this.check(request, { privileges: names });
  }

  async check(
    request: Request,
    asked: { privileges?: string[]; refresh?: boolean; returnTo?: string } = {},
  ): Promise<Outcome> {
    const wanted = (asked.privileges ?? [])
      .flat()
      .map((name) => this.privileges.get(name));
    const visit = await this.#visit(request);

    if (!(await this.#configured(visit))) {
      return { response: this.#refuse(visit, "handshake_required") };
    }

    const data =
      asked.refresh === false
        ? (await this.#readSession(visit))?.data
        : await this.#current(visit);
    const masked = this.#masked(visit, data);

    if (!masked.signedIn) {
      const refreshable =
        asked.refresh === false && !!data?.tokens?.refresh_token;

      return {
        response: this.#refuse(
          visit,
          "login_required",
          asked.returnTo,
          refreshable,
        ),
      };
    }

    try {
      for (const privilege of wanted) masked.member(privilege);
    } catch (error) {
      if (error instanceof ForbiddenError)
        return { response: forbid(visit, error), error };
      throw error;
    }

    const missing = wanted
      .filter(
        (privilege) =>
          !privilege.scopes.every((scope) => masked.permits(scope)),
      )
      .map((privilege) => privilege.name);

    if (missing.length === 0) return { masked, cookies: visit.out };

    const flow = await this.#readFlow(visit);
    const stepped = flow.steppedUp;

    if (
      stepped &&
      missing.every((name) => stepped.privileges.includes(name)) &&
      stepped.at > now() - STEP_UP_WITHIN
    ) {
      const error = new ForbiddenError(
        "insufficient_scope",
        `this account does not hold the ${missing.join(" and ")} privilege`,
        {
          scope: unique(
            missing.flatMap((name) => this.privileges.get(name).scopes),
          ).join(" "),
        },
      );

      return { response: forbid(visit, error), error };
    }

    const returnTo =
      asked.returnTo ??
      (request.method === "GET"
        ? `${visit.url.pathname}${visit.url.search}`
        : referring(request));
    const url = this.loginURL({ returnTo, privilege: missing });

    if (wantsJSON(request)) {
      return {
        response: json(
          403,
          { error: "privilege_required", privileges: missing, login_url: url },
          visit.out,
        ),
      };
    }

    return { response: redirect(url, visit.out) };
  }

  async protect(request: Request, ...names: string[]): Promise<Outcome> {
    const wanted = names.flat().map((name) => this.privileges.get(name));
    const visit = await this.#visit(request);
    let verifier: Verifier | undefined;
    let claims: Claims;

    try {
      verifier = await this.#verifier(visit);
      claims = await verifier.authenticate(request);
    } catch (error) {
      if (verifier && error instanceof InvalidTokenError) {
        const headers = new Headers({ "cache-control": "no-store" });
        for (const value of verifier.challengeHeaders(error))
          headers.append("www-authenticate", value);

        return {
          response: Response.json(
            { error: "invalid_token", error_description: describe(error) },
            { status: 401, headers },
          ),
        };
      }

      return {
        response: json(
          503,
          {
            error: "temporarily_unavailable",
            error_description: "the token could not be checked",
          },
          [],
        ),
      };
    }

    const masked = new Masked({
      claims,
      scopes: scopesOf(claims),
      signedIn: true,
      privileges: this.privileges,
      accessToken: presented(request),
      tokenType: claims.cnf?.jkt ? "DPoP" : "Bearer",
      expiresAt: claims.exp,
      accountURL: `${visit.issuerURL}/`,
    });

    try {
      for (const privilege of wanted) {
        for (const scope of privilege.scopes) {
          if (!masked.permits(scope)) {
            throw new ForbiddenError(
              "insufficient_scope",
              `this token does not carry ${scope}`,
              {
                scope: privilege.scopes.join(" "),
              },
            );
          }
        }

        masked.member(privilege);
      }
    } catch (error) {
      if (!(error instanceof ForbiddenError)) throw error;

      const headers = new Headers({ "cache-control": "no-store" });
      const scope = error.scope ? `, scope="${quote(error.scope)}"` : "";

      headers.set(
        "www-authenticate",
        `Bearer error="${error.code}", error_description="${quote(error.description)}"${scope}, resource_metadata="${this.#metadataURL(visit)}"`,
      );

      return {
        response: Response.json(
          { error: error.code, error_description: error.description },
          { status: 403, headers },
        ),
      };
    }

    return { masked, cookies: [] };
  }

  async guard(request: Request, ...names: string[]): Promise<Outcome> {
    if (request.headers.get("authorization"))
      return this.protect(request, ...names);

    const visit = await this.#visit(request);
    const session = await this.#readSession(visit);

    if (!session?.data.tokens && !(await this.#configured(visit))) {
      return this.protect(request, ...names);
    }

    if (!session?.data.tokens && wantsJSON(request)) {
      return this.protect(request, ...names);
    }

    return this.require(request, ...names);
  }

  async metadata(request: Request): Promise<Record<string, unknown>> {
    const visit = await this.#visit(request);
    const scopes = this.#options.resourceScopes ?? [];
    const answer: Record<string, unknown> = {
      resource: visit.resource,
      authorization_servers: [visit.issuerURL],
      bearer_methods_supported: ["header"],
      dpop_signing_alg_values_supported: [
        "ES256",
        "ES384",
        "ES512",
        "PS256",
        "PS384",
        "PS512",
        "RS256",
      ],
    };

    if (scopes.length > 0) answer.scopes_supported = scopes;

    return answer;
  }

  async connection(request: Request): Promise<Connection> {
    const visit = await this.#visit(request);
    const held = await this.#credentials.read(request);

    return held?.client_id
      ? { connected: true, client_id: held.client_id, issuer: visit.issuerURL }
      : { connected: false, issuer: visit.issuerURL };
  }

  async registered(request: Request): Promise<boolean> {
    const visit = await this.#visit(request);
    const held = await this.#credentials.read(request);

    if (!held?.registration_client_uri || !held.registration_access_token)
      return true;

    try {
      await (await this.#issuer(visit.issuerURL)).readRegistration(
        registrationOf(held),
      );
      return true;
    } catch (error) {
      return !(
        error instanceof MasksError &&
        [401, 403, 404].includes(error.status ?? 0)
      );
    }
  }

  async disconnect(request: Request): Promise<boolean> {
    if (!this.#credentials.clear) return false;

    const visit = await this.#visit(request);
    const held = await this.#credentials.read(request);

    if (held?.registration_client_uri && held.registration_access_token) {
      try {
        await (await this.#issuer(visit.issuerURL)).deleteRegistration(
          registrationOf(held),
        );
      } catch {}
    }

    await this.#credentials.clear(request);

    return true;
  }

  async client(request: Request): Promise<Client | undefined> {
    return this.#client(await this.#visit(request));
  }

  async delegations(request: Request): Promise<Delegations> {
    const visit = await this.#visit(request);
    const client = await this.#client(visit);

    if (!this.#options.delegations) {
      throw new Error(
        "masks: set delegations to the path a provider connection comes back to",
      );
    }

    if (!client)
      throw new MasksError(
        "handshake_required",
        "this app has not shaken hands with masks",
      );

    return new Delegations(
      client,
      `${visit.origin}${localPath(this.#options.delegations) ?? "/"}`,
    );
  }

  async startDelegation(
    request: Request,
    provider: string,
    asked: { prompt?: string; maxAge?: number } = {},
  ): Promise<Response> {
    const visit = await this.#visit(request);
    const masked = this.#masked(visit, await this.#current(visit));

    if (!masked.signedIn || !masked.subject) {
      return this.#refuse(visit, "login_required");
    }

    const started = await (await this.delegations(request)).start({
      provider,
      ...asked,
    });
    const flow = await this.#readFlow(visit);

    flow.delegations = keep(flow.delegations, started.state, {
      verifier: started.verifier,
      nonce: started.nonce,
      provider: started.provider,
      redirectURI: started.redirectURI,
      account: masked.subject,
      until: now() + FLOW_LIFETIME,
    });
    await this.#writeFlow(visit, flow);

    return redirect(started.url, visit.out);
  }

  async finishDelegation(
    request: Request,
  ): Promise<{ connection: DelegatedConnection; cookies: string[] }> {
    const visit = await this.#visit(request);
    const flow = await this.#readFlow(visit);
    const state = visit.url.searchParams.get("state") ?? "";
    const pending = claim(flow.delegations, state);

    if (!pending) {
      throw new DelegationRefused(
        "invalid_state",
        "that connection was not started by this browser, or it expired",
      );
    }

    await this.#writeFlow(visit, flow);

    const masked = this.#masked(visit, await this.#current(visit));

    if (!masked.signedIn || masked.subject !== pending.account) {
      throw new DelegationRefused(
        "access_denied",
        "that connection was started by somebody other than the person signed in",
      );
    }

    const connection = await (await this.delegations(request)).finish(
      visit.url.searchParams,
      { ...pending, state, url: "" },
    );

    if (connection.account && connection.account !== pending.account) {
      throw new DelegationRefused(
        "access_denied",
        "masks connected that provider for another account",
      );
    }

    return { connection, cookies: visit.out };
  }

  async #start(visit: Visit): Promise<Response> {
    let client = await this.#client(visit);

    if (client && !(await this.registered(visit.request))) {
      await this.disconnect(visit.request);
      client = await this.#client(visit);
    }

    if (!client) return redirect(this.handshakePath, visit.out);

    const params = visit.url.searchParams;
    const named = this.privileges.known(
      (params.get("privilege") ?? "").split(/\s+/).filter(Boolean),
    );
    const scope = named.length
      ? unique([
          ...this.scope,
          ...named.flatMap((name) => this.privileges.get(name).scopes),
        ])
      : this.scope;
    const organization =
      organizationKey(params.get("organization")) ??
      organizationKey(await resolve(this.#options.organization, visit.request));
    const redirectURI = this.#redirectURI(visit);
    const resource = [visit.resource];
    const started = await client.start({
      redirectURI,
      scope,
      resource,
      organization,
    });
    const flow = await this.#readFlow(visit);
    let returnTo = localPath(params.get("return_to") ?? undefined);

    if (returnTo?.startsWith(this.basePath)) returnTo = undefined;

    flow.requests = keep(flow.requests, started.state, {
      verifier: started.verifier,
      nonce: started.nonce,
      returnTo,
      redirectURI,
      resource,
      until: now() + FLOW_LIFETIME,
    });

    if (named.length > 0) flow.steppedUp = { privileges: named, at: now() };

    await this.#writeFlow(visit, flow);

    return redirect(started.url, visit.out);
  }

  async #callback(visit: Visit): Promise<Response> {
    const params = visit.url.searchParams;
    const flow = await this.#readFlow(visit);
    const state = params.get("state") ?? "";
    const pending = claim(flow.requests, state);

    if (pending) await this.#writeFlow(visit, flow);

    if (params.get("error")) {
      return answer(
        visit,
        400,
        params.get("error") ?? "access_denied",
        params.get("error_description") ?? "masks did not sign you in",
      );
    }

    if (!pending) return this.#stale(visit, flow);

    const client = await this.#client(visit);

    if (!client) return redirect(this.handshakePath, visit.out);

    let signedIn: { token: Token; claims?: IdTokenClaims };

    try {
      signedIn = await client.complete(params, { ...pending, state });
    } catch (error) {
      if (
        error instanceof MasksError &&
        error.code === "invalid_client" &&
        (await this.disconnect(visit.request))
      ) {
        return redirect(this.handshakePath, visit.out);
      }

      throw error;
    }

    const identity = await this.#identity(
      client,
      signedIn.token,
      signedIn.claims,
    );
    const signedInAt = now();

    await this.#writeSession(
      visit,
      {
        tokens: held(signedIn.token),
        identity,
        signedInAt,
        expiresAt: signedInAt + this.maxAge,
      },
      true,
    );

    return redirect(
      pending.returnTo ?? this.#options.afterSignIn ?? "/",
      visit.out,
    );
  }

  async #stale(visit: Visit, flow: FlowData): Promise<Response> {
    const masked = this.#masked(visit, await this.#current(visit));

    if (masked.signedIn)
      return redirect(this.#options.afterSignIn ?? "/", visit.out);

    if (
      !wantsJSON(visit.request) &&
      (flow.restartedAt ?? 0) < now() - RESTART_WITHIN
    ) {
      flow.restartedAt = now();
      await this.#writeFlow(visit, flow);

      return redirect(this.basePath, visit.out);
    }

    return answer(
      visit,
      400,
      "invalid_state",
      "that sign-in request is not one this browser started, or it expired",
    );
  }

  async #refreshRoute(visit: Visit): Promise<Response> {
    const returnTo = localPath(
      visit.url.searchParams.get("return_to") ?? undefined,
    );
    const masked = this.#masked(visit, await this.#current(visit));

    if (masked.signedIn)
      return redirect(returnTo ?? this.#options.afterSignIn ?? "/", visit.out);

    return redirect(this.loginURL({ returnTo }), visit.out);
  }

  async #sessionRoute(visit: Visit): Promise<Response> {
    if (!(await this.#configured(visit)))
      return this.#refuseJSON(visit, "handshake_required");

    const masked = this.#masked(visit, await this.#current(visit));

    if (!masked.signedIn) return this.#refuseJSON(visit, "login_required");

    return json(200, masked.toJSON(), visit.out);
  }

  async #avatar(visit: Visit): Promise<Response> {
    const data = await this.#current(visit);
    const masked = this.#masked(visit, data);
    const photo = masked.avatars.photo;

    if (!masked.signedIn || !photo || !data?.tokens)
      return text(404, "not found", visit.out);

    return avatarResponse(
      {
        photo,
        issuer: visit.issuerURL,
        authorization: `${data.tokens.token_type} ${data.tokens.access_token}`,
        size: visit.url.searchParams.get("size"),
        fetch: this.#options.fetch ?? globalThis.fetch,
        limit: this.#options.avatars,
      },
      visit.out,
    );
  }

  async #logout(visit: Visit): Promise<Response> {
    if (!sameOrigin(visit.request, visit.origin)) {
      return answer(
        visit,
        403,
        "forbidden",
        "signing out is only asked for from this app",
      );
    }

    const session = await this.#readSession(visit);
    const client = await this.#client(visit);
    const refresh = session?.data.tokens?.refresh_token;

    if (client && refresh) {
      try {
        await client.revoke(refresh, "refresh_token");
      } catch {}
    }

    await this.#forget(visit);

    const everywhere =
      this.#options.signOutOfIssuer === true ||
      visit.url.searchParams.has("everywhere");
    let upstream: string | undefined;

    if (everywhere && client) {
      try {
        const state = random(16);
        const flow = await this.#readFlow(visit);

        flow.logouts = keep(flow.logouts, state, {
          until: now() + FLOW_LIFETIME,
        });
        await this.#writeFlow(visit, flow);

        upstream = client.endSessionURL({
          postLogoutRedirectURI: this.#handshakeReturn(visit),
          state,
        });
      } catch {
        upstream = undefined;
      }
    }

    if (wantsJSON(visit.request)) {
      return json(
        200,
        { signed_in: false, ...(upstream ? { logout_url: upstream } : {}) },
        visit.out,
      );
    }

    return redirect(
      upstream ?? this.#options.afterSignOut ?? "/",
      visit.out,
      303,
    );
  }

  async #backchannel(visit: Visit): Promise<Response> {
    const client = await this.#client(visit);

    if (!client)
      return answer(
        visit,
        400,
        "invalid_request",
        "this app has not shaken hands with masks",
        true,
      );

    const form = new URLSearchParams(await visit.request.text());
    const token = form.get("logout_token");

    if (!token)
      return answer(
        visit,
        400,
        "invalid_request",
        "logout_token is required",
        true,
      );

    let logout: LogoutToken;

    try {
      logout = await client.logoutToken(token);
    } catch (error) {
      if (error instanceof InvalidTokenError) {
        return answer(visit, 400, "invalid_request", describe(error), true);
      }

      throw error;
    }

    const at = Math.max(Number(logout.iat) || 0, now());

    if (logout.sid)
      await this.#logouts.record(
        `${visit.issuerURL} sid ${logout.sid}`,
        at,
        this.maxAge,
      );
    if (logout.sub && !logout.sid) {
      await this.#logouts.record(
        `${visit.issuerURL} sub ${logout.sub}`,
        at,
        this.maxAge,
      );
    }

    if (this.#options.onLogout)
      await this.#options.onLogout(logout, visit.request);

    return new Response(null, {
      status: 200,
      headers: { "cache-control": "no-store" },
    });
  }

  async #handshakeShow(visit: Visit): Promise<Response> {
    if (!(await this.#configured(visit))) return this.#beginHandshake(visit);

    const refused = await this.#manager(visit);
    if (refused) return refused;

    return page(
      "This app is connected",
      `<p>Reconnecting replaces the credentials it holds with a fresh pair. It is how you rotate them, and how you move this app to another account. No secret passes through your browser.</p>
<p>The app stops working between the approval and the moment it picks the new credentials up.</p>
<form method="post" action="${escapeHTML(this.handshakePath)}"><button type="submit">Reconnect it</button></form>
${this.#credentials.clear ? `<form method="post" action="${escapeHTML(`${this.handshakePath}/disconnect`)}"><button type="submit">Disconnect it</button></form>` : ""}`,
      visit.out,
    );
  }

  async #handshakeCreate(visit: Visit): Promise<Response> {
    if (!sameOrigin(visit.request, visit.origin)) {
      return answer(
        visit,
        403,
        "forbidden",
        "a handshake is only started from this app",
      );
    }

    if (await this.#configured(visit)) {
      const refused = await this.#manager(visit);
      if (refused) return refused;
    }

    return this.#beginHandshake(visit);
  }

  async #handshakeDestroy(visit: Visit): Promise<Response> {
    if (!sameOrigin(visit.request, visit.origin)) {
      return answer(
        visit,
        403,
        "forbidden",
        "a disconnect is only asked for from this app",
      );
    }

    if (!(await this.#configured(visit)))
      return redirect(this.handshakePath, visit.out, 303);

    const refused = await this.#manager(visit);
    if (refused) return refused;

    if (!(await this.disconnect(visit.request))) {
      return answer(
        visit,
        400,
        "invalid_request",
        "the credential store cannot forget this connection",
      );
    }

    await this.#forget(visit);

    if (wantsJSON(visit.request))
      return json(200, { connected: false }, visit.out);

    return redirect(this.handshakePath, visit.out, 303);
  }

  async #handshakeCallback(visit: Visit): Promise<Response> {
    const params = visit.url.searchParams;
    const state = params.get("state") ?? "";
    const flow = await this.#readFlow(visit);

    if (claim(flow.logouts, state)) {
      await this.#writeFlow(visit, flow);

      return redirect(this.#options.afterSignOut ?? "/", visit.out);
    }

    if (!claim(flow.handshakes, state)) {
      return answer(
        visit,
        400,
        "invalid_state",
        "that connection request is not one this browser started, or it expired",
      );
    }

    await this.#writeFlow(visit, flow);

    if (await this.#configured(visit)) {
      const refused = await this.#manager(visit);
      if (refused) return refused;
    }

    const handshake = await this.#handshake(visit);
    const registration = await handshake.complete(params, state);

    if (!this.#credentials.write) {
      return answer(
        visit,
        500,
        "handshake_unsaved",
        "the credential store cannot save this connection; set credentials to a store that writes",
      );
    }

    await this.#credentials.write(visit.request, {
      client_id: registration.client_id,
      client_secret: registration.client_secret,
      registration_access_token: registration.registration_access_token,
      registration_client_uri: registration.registration_client_uri,
    });

    return redirect(this.basePath, visit.out);
  }

  async #beginHandshake(visit: Visit): Promise<Response> {
    const handshake = await this.#handshake(visit);
    const started = handshake.start();
    const flow = await this.#readFlow(visit);

    flow.handshakes = keep(flow.handshakes, started.state, {
      until: now() + FLOW_LIFETIME,
    });
    await this.#writeFlow(visit, flow);

    return redirect(started.url, visit.out, 303);
  }

  async #manager(visit: Visit): Promise<Response | undefined> {
    const masked = this.#masked(visit, await this.#current(visit));

    if (!masked.signedIn) {
      return redirect(this.#options.afterSignOut ?? "/", visit.out, 303);
    }

    const manages = this.#options.manages;
    let allowed = false;

    if (typeof manages === "string") allowed = masked.privilege(manages);
    else if (typeof manages === "function")
      allowed = (await manages(visit.request, masked)) === true;

    if (allowed) return undefined;

    return answer(
      visit,
      403,
      "forbidden",
      "only somebody this app lets manage its connection can reconnect or disconnect it",
    );
  }

  async #handshake(visit: Visit): Promise<Handshake> {
    const issuer = await this.#issuer(visit.issuerURL);
    const redirectURIs = [this.#redirectURI(visit)];

    if (this.#options.delegations) {
      redirectURIs.push(
        `${visit.origin}${localPath(this.#options.delegations) ?? "/"}`,
      );
    }

    return new Handshake(issuer, {
      name:
        (await resolve(this.#options.name, visit.request)) || "An application",
      resource: visit.resource,
      redirectURIs: unique(redirectURIs),
      returnTo: this.#handshakeReturn(visit),
      scope: this.#approvedScope(),
      backchannelLogoutURI:
        issuer.metadata.backchannel_logout_supported === true
          ? `${visit.origin}${this.basePath}/logout/backchannel`
          : undefined,
    });
  }

  #approvedScope(): string[] {
    const asked = unique([...this.scope, ...this.privileges.scopes()]);
    const namespace = this.#options.namespace;
    const delegated = this.#options.delegations ? [DELEGATION_SCOPE] : [];

    if (!namespace) return [...asked, ...delegated];

    return unique([
      ...asked.filter((scope) => !scope.startsWith(namespace)),
      namespace,
      ...delegated,
    ]);
  }

  async #identity(
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

  async #current(visit: Visit): Promise<SessionData | undefined> {
    const session = await this.#readSession(visit);
    const data = session?.data;

    if (!data?.tokens) return data;
    if (fresh(data.tokens)) return data;
    if (!data.tokens.refresh_token) return data;

    const client = await this.#client(visit);
    if (!client) return data;

    const key = `${visit.issuerURL} ${data.tokens.refresh_token}`;
    let pending = this.#refreshing.get(key);

    if (!pending) {
      pending = this.#refresh(visit, client, data);
      this.#refreshing.set(key, pending);
      pending.then(
        () =>
          setTimeout(
            () => this.#refreshing.delete(key),
            REMEMBER_REFRESH,
          ).unref?.(),
        () => this.#refreshing.delete(key),
      );
    }

    let refreshed: SessionData | undefined;

    try {
      refreshed = await pending;
    } catch (error) {
      if (error instanceof MasksError && error.code === "invalid_client") {
        await this.disconnect(visit.request);
        await this.#forget(visit);

        return undefined;
      }

      if (
        error instanceof MasksError &&
        (error.status ?? 0) < 500 &&
        error.status !== 429
      ) {
        await this.#forget(visit);

        return undefined;
      }

      return data;
    }

    if (!refreshed) return data;

    await this.#writeSession(visit, refreshed, false);

    return refreshed;
  }

  async #refresh(
    visit: Visit,
    client: Client,
    data: SessionData,
  ): Promise<SessionData> {
    const renewed = await client.refresh(data.tokens?.refresh_token as string, {
      resource: [visit.resource],
    });

    renewed.refresh_token ??= data.tokens?.refresh_token;

    let identity = data.identity;

    try {
      const profile = await client.userinfo(renewed);

      if (!identity?.sub || profile.sub === identity.sub) {
        identity = pick({ ...(identity ?? {}), ...profile });
      }
    } catch {}

    return { ...data, tokens: held(renewed), identity };
  }

  #masked(visit: Visit, data: SessionData | undefined): Masked {
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

  #refuse(
    visit: Visit,
    reason: "handshake_required" | "login_required",
    asked?: string,
    refreshable = false,
  ): Response {
    if (wantsJSON(visit.request)) return this.#refuseJSON(visit, reason);

    if (reason === "handshake_required")
      return redirect(this.handshakePath, visit.out);

    const returnTo =
      localPath(asked) ??
      (visit.request.method === "GET"
        ? `${visit.url.pathname}${visit.url.search}`
        : referring(visit.request));

    if (refreshable) {
      const query = returnTo
        ? `?${new URLSearchParams({ return_to: returnTo })}`
        : "";

      return redirect(`${this.basePath}/refresh${query}`, visit.out);
    }

    return redirect(this.loginURL({ returnTo }), visit.out);
  }

  #refuseJSON(
    visit: Visit,
    reason: "handshake_required" | "login_required",
  ): Response {
    if (reason === "handshake_required") {
      return json(
        401,
        { signed_in: false, error: reason, handshake_url: this.handshakePath },
        visit.out,
      );
    }

    return json(
      401,
      {
        signed_in: false,
        error: reason,
        login_url: this.loginURL({ returnTo: referring(visit.request) }),
      },
      visit.out,
    );
  }

  async #visit(request: Request): Promise<Visit> {
    const visit = new Visit(request);
    const issuer =
      (await resolve(this.#options.issuer, request)) ??
      processEnv().MASKS_ISSUER;
    const resource =
      (await resolve(this.#options.resource, request)) ??
      processEnv().MASKS_RESOURCE;

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

  async #issuer(url: string): Promise<Issuer> {
    const cached = this.#issuers.get(url);

    if (cached && Date.now() - cached.at < DISCOVERY_LIFETIME)
      return cached.issuer;

    const issuer = Issuer.discover(url, {
      fetch: this.#options.fetch,
      allowPlainHTTP: this.#options.allowPlainHTTP,
    });

    this.#issuers.set(url, { at: Date.now(), issuer });
    issuer.catch(() => {
      if (this.#issuers.get(url)?.issuer === issuer) this.#issuers.delete(url);
    });

    return issuer;
  }

  async #client(visit: Visit): Promise<Client | undefined> {
    const held = await this.#credentials.read(visit.request);

    if (!held?.client_id) return undefined;

    return new Client({
      issuer: await this.#issuer(visit.issuerURL),
      id: held.client_id,
      secret: held.client_secret,
    });
  }

  async #configured(visit: Visit): Promise<boolean> {
    return !!(await this.#credentials.read(visit.request))?.client_id;
  }

  async #verifier(visit: Visit): Promise<Verifier> {
    const key = `${visit.issuerURL} ${visit.resource}`;
    let held = this.#verifiers.get(key);

    if (!held) {
      held = new Verifier(await this.#issuer(visit.issuerURL), visit.resource, {
        publicURL: visit.origin,
        replay: this.#options.replay,
        resourceMetadata: this.#metadataURL(visit),
      });
      this.#verifiers.set(key, held);
    }

    return held;
  }

  #metadataPath(visit: Visit): string {
    const path = new URL(visit.resource).pathname.replace(/\/+$/, "");

    return `${RESOURCE_PATH}${path}`;
  }

  #metadataURL(visit: Visit): string {
    return `${visit.origin}${this.#metadataPath(visit)}`;
  }

  #redirectURI(visit: Visit): string {
    return `${visit.origin}${this.basePath}/callback`;
  }

  #handshakeReturn(visit: Visit): string {
    return `${visit.origin}${this.basePath}/handshake/callback`;
  }

  #sessionCookie(visit: Visit): string {
    return visit.secure ? "__Host-masks" : "masks";
  }

  #flowCookie(visit: Visit): string {
    return visit.secure ? "__Host-masks-flow" : "masks-flow";
  }

  async #readSession(
    visit: Visit,
  ): Promise<{ id?: string; data: SessionData } | undefined> {
    if (visit.session !== undefined) return visit.session ?? undefined;

    visit.session = null;

    const sealed = await this.#seal.unseal<{
      id?: string;
      data?: SessionData;
      until: number;
    }>(SESSION_PURPOSE, readChunked(visit.cookies, this.#sessionCookie(visit)));

    if (!sealed || !(sealed.until > now())) return undefined;

    let data = sealed.data;

    if (sealed.id && this.#options.sessions) {
      data = (await this.#options.sessions.get(sealed.id)) as
        | SessionData
        | undefined;
    }

    if (!data || (data.expiresAt ?? 0) < now()) return undefined;

    if (await this.#loggedOut(visit, data)) {
      visit.session = { id: sealed.id, data };
      await this.#forget(visit);

      return undefined;
    }

    visit.session = { id: sealed.id, data };

    return visit.session;
  }

  async #loggedOut(visit: Visit, data: SessionData): Promise<boolean> {
    const since = data.signedInAt ?? 0;
    const sid = data.identity?.sid;
    const sub = data.identity?.sub;

    if (typeof sid === "string" && sid !== "") {
      const at = await this.#logouts.since(`${visit.issuerURL} sid ${sid}`);

      if (at !== undefined && at >= since) return true;
    }

    if (typeof sub === "string" && sub !== "") {
      const at = await this.#logouts.since(`${visit.issuerURL} sub ${sub}`);

      if (at !== undefined && at > since) return true;
    }

    return false;
  }

  async #writeSession(
    visit: Visit,
    data: SessionData,
    rotate: boolean,
  ): Promise<void> {
    if (visit.session === undefined) await this.#readSession(visit);

    const store = this.#options.sessions;
    const until = data.expiresAt ?? now() + this.maxAge;
    const previous = visit.session?.id;
    let sealed: string;

    if (store) {
      const id = rotate || !previous ? random(32) : previous;

      await store.set(id, data, Math.max(1, until - now()));
      if (previous && previous !== id) await store.delete(previous);

      sealed = await this.#seal.seal(SESSION_PURPOSE, { id, until });
      visit.session = { id, data };
    } else {
      sealed = await this.#seal.seal(SESSION_PURPOSE, { data, until });
      visit.session = { data };
    }

    this.#setCookies(
      visit,
      writeChunked(visit.cookies, this.#sessionCookie(visit), sealed, {
        secure: visit.secure,
        maxAge: Math.max(1, until - now()),
      }),
    );
  }

  async #forget(visit: Visit): Promise<void> {
    const id = visit.session?.id;

    if (id && this.#options.sessions) await this.#options.sessions.delete(id);

    visit.session = null;

    this.#setCookies(
      visit,
      writeChunked(visit.cookies, this.#sessionCookie(visit), undefined, {
        secure: visit.secure,
      }),
    );
  }

  async #readFlow(visit: Visit): Promise<FlowData> {
    if (visit.flow) return visit.flow;

    const sealed = await this.#seal.unseal<{ flow: FlowData; until: number }>(
      FLOW_PURPOSE,
      visit.cookies.get(this.#flowCookie(visit)),
    );

    visit.flow = sealed && sealed.until > now() ? sealed.flow : {};

    return visit.flow;
  }

  async #writeFlow(visit: Visit, flow: FlowData): Promise<void> {
    visit.flow = flow;

    const sealed = await this.#seal.seal(FLOW_PURPOSE, {
      flow,
      until: now() + FLOW_LIFETIME,
    });

    this.#setCookies(
      visit,
      writeChunked(visit.cookies, this.#flowCookie(visit), sealed, {
        secure: visit.secure,
        maxAge: FLOW_LIFETIME,
      }),
    );
  }

  #setCookies(visit: Visit, written: string[]): void {
    for (const line of written) {
      const name = line.slice(0, line.indexOf("="));
      const at = visit.out.findIndex((held) => held.startsWith(`${name}=`));

      if (at >= 0) visit.out.splice(at, 1);
      visit.out.push(line);
    }
  }
}

function now(): number {
  return Math.floor(Date.now() / 1000);
}

function fresh(tokens: HeldTokens): boolean {
  return !tokens.expires_at || tokens.expires_at - now() > REFRESH_LEEWAY;
}

function held(token: Token): HeldTokens {
  return {
    access_token: token.access_token,
    token_type: token.token_type || "Bearer",
    refresh_token: token.refresh_token,
    scope: token.scope ?? "",
    expires_at: token.expires_at,
  };
}

function pick(claims: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(
    IDENTITY.filter(
      (name) => claims[name] !== undefined && claims[name] !== null,
    ).map((name) => [name, claims[name]]),
  );
}

function keep<T extends { until: number }>(
  held: Record<string, T> | undefined,
  id: string,
  entry: T,
): Record<string, T> {
  const live = Object.entries(held ?? {}).filter(
    ([, value]) => value?.until > now(),
  );

  return Object.fromEntries(
    [...live, [id, entry] as [string, T]].slice(-FLOW_LIMIT),
  );
}

function claim<T extends { until: number }>(
  held: Record<string, T> | undefined,
  id: string,
): T | undefined {
  if (!held || !id) return undefined;

  const match = Object.keys(held).find((key) => constantEqual(key, id));

  if (!match) return undefined;

  const found = held[match];
  delete held[match];

  return found && found.until > now() ? found : undefined;
}

async function resolve<T>(
  value: PerRequest<T> | undefined,
  request: Request,
): Promise<T | undefined> {
  if (typeof value === "function") {
    return (value as (request: Request) => T | Promise<T>)(request);
  }

  return value;
}

export function localPath(
  value: string | null | undefined,
): string | undefined {
  if (
    typeof value !== "string" ||
    !value.startsWith("/") ||
    value.startsWith("//")
  )
    return undefined;
  if (unsafe(value, 0x20) || value.includes("\\")) return undefined;

  try {
    const parsed = new URL(value, "http://masks.invalid");

    if (
      parsed.origin !== "http://masks.invalid" ||
      parsed.pathname.startsWith("//")
    )
      return undefined;

    return `${parsed.pathname}${parsed.search}`;
  } catch {
    return undefined;
  }
}

function referring(request: Request): string | undefined {
  const referer = request.headers.get("referer");

  if (!referer) return undefined;

  try {
    const parsed = new URL(referer);

    return localPath(`${parsed.pathname}${parsed.search}`);
  } catch {
    return undefined;
  }
}

export function wantsJSON(request: Request): boolean {
  if (
    request.headers.get("x-requested-with")?.toLowerCase() === "xmlhttprequest"
  )
    return true;

  return !(request.headers.get("accept") ?? "").includes("text/html");
}

export function sameOrigin(request: Request, origin: string): boolean {
  const site = request.headers.get("sec-fetch-site");

  if (site && site !== "same-origin" && site !== "none") return false;

  const named = request.headers.get("origin");

  if (named !== null && named !== origin) return false;

  return true;
}

function presented(request: Request): string | undefined {
  return request.headers
    .get("authorization")
    ?.match(/^(?:Bearer|DPoP)[ \t]+(\S+)\s*$/i)?.[1];
}

function describe(error: Error): string {
  return error.message.replace(/^masks: (invalid token: )?/, "");
}

function quote(value: string): string {
  return [...value]
    .map((found) =>
      unsafe(found, 0x1f) || found === '"' || found === "\\" ? " " : found,
    )
    .join("")
    .trim();
}

function unsafe(value: string, highest: number): boolean {
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);

    if (code <= highest || code === 0x7f) return true;
  }

  return false;
}

function isNetwork(error: unknown): boolean {
  return (
    error instanceof TypeError && /fetch|network|connect/i.test(error.message)
  );
}

function registrationOf(held: Credentials): Registration {
  return {
    client_id: held.client_id,
    client_secret: held.client_secret,
    registration_access_token: held.registration_access_token,
    registration_client_uri: held.registration_client_uri,
  };
}

function headersWith(
  cookies: string[],
  extra: Record<string, string> = {},
): Headers {
  const headers = new Headers(extra);

  for (const cookie of cookies) headers.append("set-cookie", cookie);

  return headers;
}

export function redirect(
  location: string,
  cookies: string[],
  status = 302,
): Response {
  return new Response(null, {
    status,
    headers: headersWith(cookies, { location, "cache-control": "no-store" }),
  });
}

export function json(
  status: number,
  body: unknown,
  cookies: string[],
  extra: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: headersWith(cookies, {
      "content-type": "application/json",
      "cache-control": "no-store",
      ...extra,
    }),
  });
}

function text(status: number, body: string, cookies: string[]): Response {
  return new Response(body, {
    status,
    headers: headersWith(cookies, {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    }),
  });
}

function answer(
  visit: Visit,
  status: number,
  code: string,
  description: string,
  asJSON = false,
): Response {
  if (asJSON || wantsJSON(visit.request)) {
    return json(
      status,
      { error: code, error_description: description },
      visit.out,
    );
  }

  return text(status, `${code}: ${description}`, visit.out);
}

function forbid(visit: Visit, error: ForbiddenError): Response {
  return answer(visit, 403, error.code, error.description);
}

function escapeHTML(value: string): string {
  return value.replace(/[&<>"']/g, (found) => `&#${found.charCodeAt(0)};`);
}

function page(title: string, body: string, cookies: string[]): Response {
  return new Response(
    `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escapeHTML(title)}</title><style>body{font-family:system-ui,sans-serif;max-width:36rem;margin:4rem auto;padding:0 1rem;line-height:1.5}form{display:inline-block;margin-right:.5rem}</style></head><body><h1>${escapeHTML(title)}</h1>${body}</body></html>`,
    {
      status: 200,
      headers: headersWith(cookies, {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "no-store",
        "content-security-policy":
          "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'",
        "x-frame-options": "DENY",
      }),
    },
  );
}
