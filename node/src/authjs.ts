import { decodeJwt } from "jose";
import type { NextAuthConfig, NextAuthResult, Session } from "next-auth";
import { avatarResponse } from "./app/avatar.js";
import { parseCookies, replaceCookies, serialize } from "./app/cookies.js";
import { DEFAULT_SCOPE } from "./app/core.js";
import { type CredentialStore, defaultCredentials } from "./app/credentials.js";
import { IssuerCache } from "./app/issuers.js";
import { acceptLogout, departed } from "./app/logouts.js";
import { Masked, type MaskedJSON } from "./app/masked.js";
import {
  approvedScope,
  type Privilege,
  type PrivilegeSpec,
  Privileges,
  unique,
} from "./app/privileges.js";
import { type Renewal, renew } from "./app/refresh.js";
import {
  isNetwork,
  localPath,
  PATH_HEADER,
  readForm,
  sameOrigin,
  wantsJSON,
} from "./app/requests.js";
import { errorResponse, json, redirect, text } from "./app/responses.js";
import { connectedPage } from "./app/routes.js";
import { Sealer } from "./app/seal.js";
import { claim, fresh, keep, now, pick } from "./app/session.js";
import { memoryStore, processEnv, type Store, shared } from "./app/stores.js";
import { avatarsOf, ForbiddenError, organizationKey } from "./claims.js";
import { type Client, constantEqual, scopes as scopesOf } from "./client.js";
import {
  type Connection,
  DELEGATION_SCOPE,
  DelegationRefused,
  Delegations,
  type PendingDelegation,
  pendingFor,
} from "./delegations.js";
import {
  InvalidTokenError,
  isMasksError,
  MasksError,
  UnavailableError,
} from "./errors.js";
import { Handshake, originOf } from "./handshake.js";
import type { LogoutToken } from "./idtoken.js";
import type { Issuer } from "./issuer.js";
import { random } from "./key.js";

type NextAuth = (
  config: (request: Request | undefined) => Promise<NextAuthConfig>,
) => NextAuthResult;

type Handler = NextAuthResult["handlers"]["GET"];
type Incoming = Parameters<Handler>[0];

export interface MasksAuthOptions extends Omit<NextAuthConfig, "providers"> {
  providers?: NextAuthConfig["providers"];
  issuer?: string;
  resource?: string;
  name?: string;
  id?: string;
  label?: string;
  scope?: string[];
  namespace?: string;
  organization?: string;
  privileges?: Record<string, PrivilegeSpec>;
  manages?:
    | string
    | ((request: Request, masked: Masked) => boolean | Promise<boolean>);
  credentials?: CredentialStore;
  store?: Store;
  signOutOfIssuer?: boolean;
  delegations?: string;
  avatarBytes?: number;
  onLogout?: (logout: LogoutToken, request: Request) => void | Promise<void>;
  allowPlainHTTP?: boolean;
}

export interface HeldSignIn {
  iss: string;
  sub: string;
  sid?: string;
  at: number;
  access_token: string;
  token_type: string;
  refresh_token?: string;
  expires_at?: number;
  scope: string;
  identity: Record<string, unknown>;
}

declare module "next-auth" {
  interface Session {
    masks?: MaskedJSON;
  }
}

export interface MasksAuthResult extends NextAuthResult {
  masks: MasksAuth;
  requireAuth: (...privileges: string[]) => Promise<Masked>;
  accessToken: () => Promise<string | undefined>;
  proxy: (request: Request) => Promise<Response>;
}

const PREFIX = "/masks";
const HANDSHAKE_COOKIE = "masks-handshake";
const STEPPED_COOKIE = "masks-stepped";
const FAREWELL_COOKIE = "masks-farewell";
const DELEGATION_COOKIE = "masks-delegation";
const DELEGATION_PURPOSE = "authjs delegation";
const FLOW_LIFETIME = 3600;
const STEP_UP_WITHIN = 300;
const NOWHERE = "https://masks.invalid/unconnected";
const MASKS_OPTIONS = new Set([
  "issuer",
  "resource",
  "name",
  "id",
  "label",
  "scope",
  "namespace",
  "organization",
  "privileges",
  "manages",
  "credentials",
  "store",
  "signOutOfIssuer",
  "delegations",
  "avatarBytes",
  "onLogout",
  "allowPlainHTTP",
]);

export function masksAuth(
  NextAuth: NextAuth,
  options: MasksAuthOptions = {},
): MasksAuthResult {
  const masks = new MasksAuth(options);
  const result = NextAuth((request) => masks.config(request));

  return masks.bind(result);
}

export class MasksAuth {
  readonly id: string;
  readonly privileges: Privileges;
  readonly scope: string[];
  readonly #options: MasksAuthOptions;
  readonly #credentials: CredentialStore;
  readonly #store: Store;
  readonly #issuers = new IssuerCache(() => ({
    allowPlainHTTP: this.#options.allowPlainHTTP,
  }));
  #result?: NextAuthResult;
  #sealer?: Sealer;

  constructor(options: MasksAuthOptions = {}) {
    this.#options = options;
    this.id = options.id ?? "masks";
    this.privileges = new Privileges(options.privileges);
    this.scope = options.scope ?? DEFAULT_SCOPE;
    this.#credentials =
      options.credentials ??
      defaultCredentials(processEnv(), `AUTH_${this.#envName}`, "MASKS_CLIENT");
    this.#store = options.store ?? shared("store", () => memoryStore());
  }

  get #envName(): string {
    return this.id.toUpperCase().replace(/[^A-Z0-9]/g, "_");
  }

  get basePath(): string {
    if (this.#options.basePath) return trim(this.#options.basePath);

    const env = processEnv();
    const url = env.AUTH_URL ?? env.NEXTAUTH_URL;

    if (url) {
      try {
        const { pathname } = new URL(url);

        if (pathname !== "/") return trim(pathname);
      } catch {}
    }

    return "/api/auth";
  }

  get issuerURL(): string {
    const env = processEnv();
    const named =
      this.#options.issuer ??
      env[`AUTH_${this.#envName}_ISSUER`] ??
      env.MASKS_ISSUER;

    if (!named) {
      throw new Error(
        `masks: set AUTH_${this.#envName}_ISSUER, or pass issuer, to name the masks server`,
      );
    }

    return named.replace(/\/+$/, "");
  }

  signInPath(
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

    if (returnTo) query.set("callbackUrl", returnTo);
    if (organization) query.set("organization", organization);
    if (privileges.length > 0) query.set("privilege", privileges.join(" "));

    const held = query.toString();
    const path = `${this.basePath}${PREFIX}/signin`;

    return held ? `${path}?${held}` : path;
  }

  get logoutPath(): string {
    return `${this.basePath}${PREFIX}/logout`;
  }

  get avatarPath(): string {
    return `${this.basePath}${PREFIX}/avatar`;
  }

  get handshakePath(): string {
    return `${this.basePath}${PREFIX}/handshake`;
  }

  bind(result: NextAuthResult): MasksAuthResult {
    this.#result = result;

    const wrap =
      (original: Handler): Handler =>
      async (request: Incoming) =>
        (await this.handle(request)) ??
        (this.#callback(request)
          ? this.#replacing(request, original)
          : original(request));

    return {
      ...result,
      handlers: {
        GET: wrap(result.handlers.GET),
        POST: wrap(result.handlers.POST),
      },
      masks: this,
      requireAuth: (...privileges) => this.requireAuth(...privileges),
      accessToken: () => this.accessToken(),
      proxy: (request) => this.proxy(request),
    } as MasksAuthResult;
  }

  #callback(request: Request): boolean {
    return (
      new URL(request.url).pathname === `${this.basePath}/callback/${this.id}`
    );
  }

  async #replacing(request: Incoming, original: Handler): Promise<Response> {
    const before = await this.#signInFrom(request.headers).catch(
      () => undefined,
    );
    const answer = await original(request);
    const renewed = answer.headers
      .getSetCookie()
      .some(
        (cookie) =>
          /^(__Secure-)?authjs\.session-token(\.\d+)?=[^;]/.test(cookie) &&
          !/;\s*Max-Age=0/i.test(cookie),
      );

    if (before?.refresh_token && renewed) {
      await this.#revoke(before.refresh_token);
    }

    return answer;
  }

  async config(request?: Request): Promise<NextAuthConfig> {
    const held = await this.#requestFor(request);
    const credentials = await this.#credentials.read(held);
    const {
      providers = [],
      callbacks = {},
      events = {},
      session,
    } = this.#options;
    const rest = Object.fromEntries(
      Object.entries(this.#options).filter(([key]) => !MASKS_OPTIONS.has(key)),
    );

    return {
      ...rest,
      basePath: this.basePath,
      session: { ...session, strategy: "jwt" },
      providers: [
        credentials
          ? this.#provider(credentials)
          : this.#unconnected(new URL(held.url).origin),
        ...providers,
      ],
      callbacks: {
        ...callbacks,
        signIn: async (params) => {
          if (params.account?.provider === this.id) {
            if (params.account.type !== "oidc") return false;
            if (!(await this.#credentials.read(held))) return false;
          }

          return callbacks.signIn ? callbacks.signIn(params) : true;
        },
        jwt: async (params) => {
          const token = await this.#jwt(params);

          if (token === null) return null;
          if (!callbacks.jwt) return token;

          return callbacks.jwt({ ...params, token });
        },
        session: async (params) => {
          const shaped = this.#session(params);

          if (!callbacks.session) return shaped;

          return callbacks.session({
            ...params,
            session: shaped,
          } as Parameters<NonNullable<typeof callbacks.session>>[0]);
        },
      },
      events: {
        ...events,
        signOut: async (message) => {
          const held =
            "token" in message ? heldOf(message.token?.masks) : undefined;

          if (held?.refresh_token) await this.#revoke(held.refresh_token);

          await events.signOut?.(message);
        },
      },
    };
  }

  async handle(request: Request): Promise<Response | undefined> {
    const url = new URL(request.url);
    const base = `${this.basePath}${PREFIX}`;

    if (url.pathname !== base && !url.pathname.startsWith(`${base}/`)) {
      return undefined;
    }

    const route = url.pathname.slice(base.length).replace(/\/+$/, "") || "/";
    const method = request.method.toUpperCase();

    try {
      switch (`${method} ${route}`) {
        case "GET /signin":
          return await this.#signInRoute(request);
        case "GET /handshake":
          return await this.#handshakeShow(request);
        case "POST /handshake":
          return await this.#handshakeCreate(request);
        case "POST /handshake/disconnect":
        case "DELETE /handshake":
          return await this.#handshakeDestroy(request);
        case "GET /handshake/callback":
          return await this.#handshakeCallback(request);
        case "GET /logout":
        case "POST /logout":
          return await this.#logout(request);
        case "GET /logout/return":
          return this.#logoutReturn(request);
        case "GET /avatar":
          return await this.#avatar(request);
        case "POST /logout/backchannel":
          return await this.#backchannel(request);
        default:
          return text(404, "not found", []);
      }
    } catch (error) {
      if (isMasksError(error)) {
        return errorResponse(
          request,
          400,
          error.code,
          error.description ?? error.code,
        );
      }

      if (error instanceof UnavailableError || isNetwork(error)) {
        return errorResponse(
          request,
          503,
          "temporarily_unavailable",
          "masks could not be reached",
        );
      }

      throw error;
    }
  }

  async requireAuth(...names: string[]): Promise<Masked> {
    const { headers, cookies } = await nextHeaders();
    const { redirect: navigate } = await nextNavigation();
    const held = await headers();
    const path = localPath(held.get(PATH_HEADER)) ?? "/";
    const session = (await this.#bound().auth()) as Session | null;
    const masked = this.masked(session);

    if (!masked.signedIn) navigate(this.signInPath({ returnTo: path }));

    const wanted = names.map((name) => this.privileges.get(name));
    const missing = wanted.filter((privilege) => !masked.holds(privilege));

    if (missing.length === 0) return masked;

    const asked = lackingScopes(masked, missing);
    const [first] = missing;

    if (asked.length === 0 && first) masked.member(first);

    if (askedBefore((await cookies()).get(STEPPED_COOKIE)?.value, asked)) {
      throw new ForbiddenError(
        "insufficient_scope",
        `masks did not grant ${asked.join(", ")}`,
      );
    }

    return navigate(this.signInPath({ returnTo: path, privilege: asked }));
  }

  masked(session: Session | null | undefined): Masked {
    return session?.masks
      ? Masked.fromJSON(session.masks, this.privileges)
      : Masked.nobody(this.privileges);
  }

  async accessToken(): Promise<string | undefined> {
    const held = await (await nextHeaders()).headers();
    const signIn = await this.#signInFrom(held);

    if (!signIn) return undefined;

    const renewal = await this.#fresh(signIn);

    return renewal.outcome === "renewed"
      ? renewal.value.access_token
      : undefined;
  }

  async delegations(request: Request): Promise<Delegations> {
    const redirectURI = this.#delegationReturn(request);

    if (!redirectURI) {
      throw new Error(
        "masks: set delegations to the path a provider connection comes back to",
      );
    }

    const client = await this.#client(request);

    if (!client) {
      throw new MasksError(
        "handshake_required",
        "this app has not shaken hands with masks",
      );
    }

    return new Delegations(client, redirectURI);
  }

  async startDelegation(
    request: Request,
    provider: string,
    asked: { prompt?: string; maxAge?: number } = {},
  ): Promise<Response> {
    const signIn = await this.#signInFrom(request.headers);

    if (!signIn) {
      const url = new URL(request.url);

      return redirect(
        this.signInPath({ returnTo: `${url.pathname}${url.search}` }),
        [],
        303,
      );
    }

    const [delegations, held] = await Promise.all([
      this.delegations(request),
      this.#pendingDelegations(request),
    ]);
    const started = await delegations.start({ provider, ...asked });
    const pending = keep(
      held,
      started.state,
      pendingFor(started, signIn.sub, now() + FLOW_LIFETIME),
    );

    return redirect(
      started.url,
      [await this.#delegationCookie(request, pending)],
      303,
    );
  }

  async finishDelegation(
    request: Request,
  ): Promise<{ connection: Connection; cookies: string[] }> {
    const url = new URL(request.url);
    const state = url.searchParams.get("state") ?? "";
    const pending = await this.#pendingDelegations(request);
    const found = claim(pending, state);

    if (!found) {
      throw new DelegationRefused(
        "invalid_state",
        "that connection was not started by this browser, or it expired",
      );
    }

    const [cookie, signIn, delegations] = await Promise.all([
      this.#delegationCookie(request, pending),
      this.#signInFrom(request.headers),
      this.delegations(request),
    ]);
    const connection = await delegations.finishFor(
      url.searchParams,
      state,
      found,
      signIn?.sub,
    );

    return { connection, cookies: [cookie] };
  }

  async proxy(request: Request): Promise<Response> {
    const { NextResponse } = await nextServer();
    const url = new URL(request.url);
    const forwarded = new Headers(request.headers);

    forwarded.set(PATH_HEADER, `${url.pathname}${url.search}`);

    const authed = this.#bound().auth as unknown as (
      request: Request,
    ) => Promise<Response>;
    const answered = await authed(request);

    if (!answered.headers.has("x-middleware-next")) return answered;

    const written = answered.headers.getSetCookie();

    if (written.length > 0) {
      forwarded.set(
        "cookie",
        replaceCookies(request.headers.get("cookie"), written),
      );
    }

    const response = NextResponse.next({ request: { headers: forwarded } });

    for (const cookie of written) response.headers.append("set-cookie", cookie);

    return response;
  }

  async #jwt(params: {
    token: Record<string, unknown>;
    account?: { provider?: string; [key: string]: unknown } | null;
    profile?: Record<string, unknown>;
  }): Promise<Record<string, unknown> | null> {
    const { token, account, profile } = params;

    if (account && account.provider === this.id) {
      if (account.type !== "oidc") return null;

      const signIn = this.#signedIn(account, profile ?? {});

      return {
        ...token,
        sub: signIn.sub,
        masks: signIn,
      };
    }

    const held = heldOf(token.masks);

    if (!held) return token;
    if (held.iss !== this.issuerURL) return null;
    if (await this.#departed(held)) return null;

    const renewal = await this.#fresh(held);

    switch (renewal.outcome) {
      case "renewed":
        return { ...token, masks: renewal.value };
      case "unregistered":
        await this.#disconnected();

        return null;
      case "refused":
        return null;
      default:
        return token;
    }
  }

  #signedIn(
    account: Record<string, unknown>,
    profile: Record<string, unknown>,
  ): HeldSignIn {
    const decoded = payloadOf(account.id_token);
    const sub = String(profile.sub ?? decoded.sub ?? "");
    const claims = decoded.sub === sub ? decoded : {};

    return {
      iss: this.issuerURL,
      sub,
      sid: typeof claims.sid === "string" ? claims.sid : undefined,
      at: Math.floor(Date.now() / 1000),
      access_token: String(account.access_token ?? ""),
      token_type: String(account.token_type ?? "Bearer"),
      refresh_token:
        typeof account.refresh_token === "string"
          ? account.refresh_token
          : undefined,
      expires_at:
        typeof account.expires_at === "number" ? account.expires_at : undefined,
      scope: typeof account.scope === "string" ? account.scope : "",
      identity: pick({ ...claims, ...profile, sub }),
    };
  }

  #session(params: {
    session: Session;
    token?: Record<string, unknown>;
  }): Session {
    const { session, token } = params;
    const held = heldOf(token?.masks);

    if (!held) return session;

    const masked = this.#maskedOf(held);

    return {
      ...session,
      user: { ...session.user, id: held.sub, image: masked.picture ?? null },
      masks: masked.toJSON(),
    };
  }

  #maskedOf(held: HeldSignIn): Masked {
    return new Masked({
      signedIn: true,
      privileges: this.privileges,
      claims: held.identity,
      scopes: scopesOf(held),
      expiresAt: held.expires_at,
      accountURL: `${held.iss}/`,
      avatarURL: this.avatarPath,
    });
  }

  #departed(held: HeldSignIn): Promise<boolean> {
    return departed(this.#store, held.iss, held, held.at);
  }

  async #fresh(held: HeldSignIn): Promise<Renewal<HeldSignIn>> {
    const refreshToken = held.refresh_token;

    if (fresh(held) || !refreshToken)
      return { outcome: "renewed", value: held };

    return renew({
      store: this.#store,
      issuer: held.iss,
      refreshToken,
      refresh: () => this.#refresh(held, refreshToken),
      expiresAt: (renewed) => renewed.expires_at,
    });
  }

  get #seal(): Sealer {
    if (!this.#sealer) {
      const env = processEnv();
      const secret =
        this.#options.secret ?? env.AUTH_SECRET ?? env.NEXTAUTH_SECRET;

      this.#sealer = new Sealer([secret ?? ""].flat());
    }

    return this.#sealer;
  }

  async #refresh(held: HeldSignIn, refreshToken: string): Promise<HeldSignIn> {
    const client = await this.#client();

    if (!client) {
      throw new UnavailableError("this app is not connected to masks");
    }

    const resource = this.#resource();
    const renewed = await client.refresh(
      refreshToken,
      resource ? { resource: [resource] } : {},
    );
    let identity = held.identity;

    try {
      const profile = await client.userinfo(renewed);

      if (profile.sub === held.sub)
        identity = pick({ ...identity, ...profile });
    } catch {}

    return {
      ...held,
      access_token: renewed.access_token,
      token_type: renewed.token_type || "Bearer",
      refresh_token: renewed.refresh_token ?? refreshToken,
      expires_at: renewed.expires_at,
      scope: renewed.scope ?? held.scope,
      identity,
    };
  }

  async #signInFrom(held: Headers): Promise<HeldSignIn | undefined> {
    const { getToken } = await nextAuthJWT();
    const cookies = parseCookies(held.get("cookie"));
    const secureCookie = [...cookies.keys()].some((name) =>
      name.startsWith("__Secure-authjs.session-token"),
    );
    const env = processEnv();
    const secret =
      this.#options.secret ?? env.AUTH_SECRET ?? env.NEXTAUTH_SECRET;

    if (!secret) return undefined;

    const token = await getToken({
      req: { headers: held },
      secret,
      secureCookie,
    });
    const signIn = heldOf(token?.masks);

    if (!signIn || signIn.iss !== this.issuerURL) return undefined;
    if (await this.#departed(signIn)) return undefined;

    return signIn;
  }

  #provider(credentials: { client_id: string; client_secret?: string }) {
    const resource = this.#resource();
    const organization = organizationKey(this.#options.organization);
    const params: Record<string, string> = { scope: this.scope.join(" ") };

    if (resource) params.resource = resource;
    if (organization) params.organization = organization;

    return {
      id: this.id,
      name: this.#options.label ?? "masks",
      type: "oidc" as const,
      issuer: this.issuerURL,
      clientId: credentials.client_id,
      clientSecret: credentials.client_secret,
      checks: ["pkce", "state", "nonce"] as ("pkce" | "state" | "nonce")[],
      idToken: false,
      authorization: { params },
      profile: (profile: Record<string, unknown>) => ({
        id: String(profile.sub ?? ""),
        name:
          (profile.name as string | undefined) ??
          (profile.preferred_username as string | undefined) ??
          null,
        email: (profile.email as string | undefined) ?? null,
        image: null,
      }),
    };
  }

  #unconnected(origin: string) {
    return {
      id: this.id,
      name: this.#options.label ?? "masks",
      type: "oauth" as const,
      clientId: "unconnected",
      clientSecret: "unconnected",
      checks: ["state"] as "state"[],
      authorization: {
        url: `${origin}${this.handshakePath}`,
        params: { scope: "openid" },
      },
      token: NOWHERE,
      userinfo: NOWHERE,
    };
  }

  async #signInRoute(request: Request): Promise<Response> {
    const params = new URL(request.url).searchParams;
    const callbackUrl = localPath(params.get("callbackUrl")) ?? "/";
    const names = (params.get("privilege") ?? "").split(/[\s,]+/);
    const privileges = this.privileges.known(names.filter(Boolean));
    const organization = organizationKey(params.get("organization"));
    const prompt = params.get("prompt");
    const asked = new URLSearchParams();
    let stepped: string | undefined;

    if (privileges.length > 0) {
      const scope = unique([
        ...this.scope,
        ...privileges.flatMap((name) => this.privileges.get(name).scopes),
      ]);

      asked.set("scope", scope.join(" "));
      stepped = serialize(
        STEPPED_COOKIE,
        encodeURIComponent(privileges.join(" ")),
        { secure: secure(request), maxAge: STEP_UP_WITHIN },
      );
    }

    if (organization) asked.set("organization", organization);
    if (prompt === "login" || prompt === "consent") asked.set("prompt", prompt);

    const started = await this.#startSignIn(request, callbackUrl, asked);

    if (stepped) started.headers.append("set-cookie", stepped);

    return started;
  }

  async #startSignIn(
    request: Request,
    callbackUrl: string,
    asked: URLSearchParams,
  ): Promise<Response> {
    const query = asked.toString();
    const { location, written } = await this.#act(
      request,
      `signin/${this.id}${query ? `?${query}` : ""}`,
      callbackUrl,
    );

    if (!location) {
      return errorResponse(
        request,
        500,
        "signin_failed",
        "Auth.js did not start the sign-in",
      );
    }

    return redirect(location, written, 303);
  }

  async #act(
    request: Request,
    action: string,
    callbackUrl: string,
  ): Promise<{ location?: string; written: string[] }> {
    const result = this.#bound();
    const origin = new URL(request.url).origin;
    const make = request.constructor as typeof Request;
    const written: string[] = [];
    const forwarded = () => {
      const headers = new Headers(request.headers);

      headers.delete("content-type");
      headers.delete("content-length");
      headers.set(
        "cookie",
        replaceCookies(request.headers.get("cookie"), written),
      );

      return headers;
    };

    const csrf = await result.handlers.GET(
      new make(`${origin}${this.basePath}/csrf`, {
        headers: forwarded(),
      }) as Incoming,
    );

    written.push(...csrf.headers.getSetCookie());

    const { csrfToken } = (await csrf.json()) as { csrfToken?: string };
    const headers = forwarded();

    headers.set("content-type", "application/x-www-form-urlencoded");

    const answered = await result.handlers.POST(
      new make(`${origin}${this.basePath}/${action}`, {
        method: "POST",
        headers,
        body: new URLSearchParams({
          csrfToken: csrfToken ?? "",
          callbackUrl: `${origin}${callbackUrl}`,
        }),
      }) as Incoming,
    );

    written.push(...answered.headers.getSetCookie());

    return { location: answered.headers.get("location") ?? undefined, written };
  }

  async #logout(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (!sameOrigin(request, url.origin)) {
      return errorResponse(
        request,
        403,
        "forbidden",
        "a sign-out is only asked for from this app",
      );
    }

    const form =
      request.method === "POST" ? await readForm(request) : url.searchParams;
    const callbackUrl =
      localPath(
        form.get("callbackUrl") ?? url.searchParams.get("callbackUrl"),
      ) ?? "/";
    const everywhere =
      form.has("everywhere") ||
      url.searchParams.has("everywhere") ||
      this.#options.signOutOfIssuer === true;
    const client = everywhere ? await this.#client(request) : undefined;
    const { written } = await this.#act(request, "signout", callbackUrl);

    if (!client) {
      if (wantsJSON(request)) return json(200, { signed_in: false }, written);

      return redirect(callbackUrl, written, 303);
    }

    const state = random();
    const target = client.endSessionURL({
      postLogoutRedirectURI: this.#logoutReturnURL(request),
      state,
    });

    written.push(
      serialize(
        hostCookie(request, FAREWELL_COOKIE),
        encodeURIComponent(`${state} ${callbackUrl}`),
        { secure: secure(request), maxAge: FLOW_LIFETIME },
      ),
    );

    if (wantsJSON(request)) {
      return json(200, { signed_in: false, logout_url: target }, written);
    }

    return redirect(target, written, 303);
  }

  #logoutReturn(request: Request): Response {
    const state = new URL(request.url).searchParams.get("state") ?? "";
    const held = parseCookies(request.headers.get("cookie")).get(
      hostCookie(request, FAREWELL_COOKIE),
    );
    const cleared = serialize(hostCookie(request, FAREWELL_COOKIE), "", {
      secure: secure(request),
      maxAge: 0,
    });
    const [expected = "", callbackUrl] = decode(held ?? "");

    if (!held || !state || !constantEqual(expected, state)) {
      return errorResponse(
        request,
        400,
        "invalid_state",
        "that sign-out is not one this browser started, or it expired",
        [cleared],
      );
    }

    return redirect(localPath(callbackUrl) ?? "/", [cleared], 303);
  }

  async #avatar(request: Request): Promise<Response> {
    const signIn = await this.#signInFrom(request.headers);
    const photo = signIn && avatarsOf(signIn.identity).photo;

    if (!signIn || !photo) return text(404, "not found", []);

    const renewal = await this.#fresh(signIn);

    if (renewal.outcome !== "renewed") return text(404, "not found", []);

    const held = renewal.value;

    return avatarResponse(
      {
        photo,
        issuer: held.iss,
        token: held,
        size: new URL(request.url).searchParams.get("size"),
        bytes: this.#options.avatarBytes,
      },
      [],
    );
  }

  async #pendingDelegations(
    request: Request,
  ): Promise<Record<string, PendingDelegation>> {
    const held = parseCookies(request.headers.get("cookie")).get(
      hostCookie(request, DELEGATION_COOKIE),
    );
    const opened = await this.#seal.unseal<Record<string, PendingDelegation>>(
      DELEGATION_PURPOSE,
      held,
    );

    return Object.fromEntries(
      Object.entries(opened ?? {}).filter(([, entry]) => entry.until > now()),
    );
  }

  async #delegationCookie(
    request: Request,
    pending: Record<string, PendingDelegation>,
  ): Promise<string> {
    const name = hostCookie(request, DELEGATION_COOKIE);

    if (Object.keys(pending).length === 0) {
      return serialize(name, "", { secure: secure(request), maxAge: 0 });
    }

    return serialize(name, await this.#seal.seal(DELEGATION_PURPOSE, pending), {
      secure: secure(request),
      maxAge: FLOW_LIFETIME,
    });
  }

  async #handshakeShow(request: Request): Promise<Response> {
    if (!(await this.#configured(request)))
      return this.#beginHandshake(request);

    const refused = await this.#manager(request);
    if (refused) return refused;

    return connectedPage(
      this.handshakePath,
      this.issuerURL,
      Boolean(this.#credentials.clear),
      [],
    );
  }

  async #handshakeCreate(request: Request): Promise<Response> {
    if (!sameOrigin(request, new URL(request.url).origin)) {
      return errorResponse(
        request,
        403,
        "forbidden",
        "a handshake is only started from this app",
      );
    }

    if (await this.#configured(request)) {
      const refused = await this.#manager(request);
      if (refused) return refused;
    }

    return this.#beginHandshake(request);
  }

  async #handshakeDestroy(request: Request): Promise<Response> {
    if (!sameOrigin(request, new URL(request.url).origin)) {
      return errorResponse(
        request,
        403,
        "forbidden",
        "a disconnect is only asked for from this app",
      );
    }

    if (!(await this.#configured(request))) {
      return redirect(this.handshakePath, [], 303);
    }

    const refused = await this.#manager(request);
    if (refused) return refused;

    if (!this.#credentials.clear) {
      return errorResponse(
        request,
        400,
        "invalid_request",
        "the credential store cannot forget this connection",
      );
    }

    const held = await this.#credentials.read(request);

    if (held?.registration_access_token) {
      try {
        await (await this.#issuer()).deleteRegistration(held);
      } catch {}
    }

    await this.#credentials.clear(request);

    if (wantsJSON(request)) return json(200, { connected: false }, []);

    return redirect("/", [], 303);
  }

  async #handshakeCallback(request: Request): Promise<Response> {
    const params = new URL(request.url).searchParams;
    const state = params.get("state") ?? "";
    const held = parseCookies(request.headers.get("cookie")).get(
      hostCookie(request, HANDSHAKE_COOKIE),
    );
    const cleared = serialize(hostCookie(request, HANDSHAKE_COOKIE), "", {
      secure: secure(request),
      maxAge: 0,
    });

    if (!held || !state || !constantEqual(held, state)) {
      return errorResponse(
        request,
        400,
        "invalid_state",
        "that connection request is not one this browser started, or it expired",
        [cleared],
      );
    }

    if (await this.#configured(request)) {
      const refused = await this.#manager(request);
      if (refused) return refused;
    }

    if (!this.#credentials.write) {
      return errorResponse(
        request,
        500,
        "handshake_unsaved",
        "the credential store cannot save this connection; set credentials to a store that writes",
        [cleared],
      );
    }

    const handshake = await this.#handshake(request);
    const registration = await handshake.complete(params, state);

    await this.#credentials.write(request, {
      client_id: registration.client_id,
      client_secret: registration.client_secret,
      registration_access_token: registration.registration_access_token,
      registration_client_uri: registration.registration_client_uri,
    });

    const started = await this.#startSignIn(
      request,
      callbackFrom(request) ?? "/",
      new URLSearchParams(),
    );

    started.headers.append("set-cookie", cleared);

    return started;
  }

  async #beginHandshake(request: Request): Promise<Response> {
    const handshake = await this.#handshake(request);
    const started = handshake.start();

    return redirect(
      started.url,
      [
        serialize(hostCookie(request, HANDSHAKE_COOKIE), started.state, {
          secure: secure(request),
          maxAge: FLOW_LIFETIME,
        }),
      ],
      303,
    );
  }

  async #handshake(request: Request): Promise<Handshake> {
    const issuer = await this.#issuer();
    const resource = this.#resource() ?? new URL(request.url).origin;
    const base = `${this.#appOrigin(request)}${this.basePath}`;
    const delegation = this.#delegationReturn(request);

    return new Handshake(issuer, {
      name: this.#options.name || new URL(resource).host,
      resource,
      redirectURIs: unique([
        `${base}/callback/${this.id}`,
        ...(delegation ? [delegation] : []),
      ]),
      returnTo: `${base}${PREFIX}/handshake/callback`,
      scope: approvedScope(
        this.scope,
        this.privileges,
        this.#options.namespace,
        delegation ? [DELEGATION_SCOPE] : [],
      ),
      backchannelLogoutURI: `${base}${PREFIX}/logout/backchannel`,
      postLogoutRedirectUri: this.#logoutReturnURL(request),
    });
  }

  async #manager(request: Request): Promise<Response | undefined> {
    const held = await this.#signInFrom(request.headers);

    if (!held) {
      return redirect(
        this.signInPath({ returnTo: this.handshakePath }),
        [],
        303,
      );
    }

    const masked = this.#maskedOf(held);

    const manages = this.#options.manages;
    let allowed = false;

    if (typeof manages === "string") allowed = masked.privilege(manages);
    else if (typeof manages === "function")
      allowed = (await manages(request, masked)) === true;

    if (allowed) return undefined;

    const asked =
      typeof manages === "string"
        ? lackingScopes(masked, [this.privileges.get(manages)])
        : [];
    const stepped = parseCookies(request.headers.get("cookie")).get(
      STEPPED_COOKIE,
    );

    if (asked.length > 0 && !askedBefore(stepped, asked)) {
      return redirect(
        this.signInPath({ returnTo: this.handshakePath, privilege: asked }),
        [],
        303,
      );
    }

    return errorResponse(
      request,
      403,
      "forbidden",
      "only somebody this app lets manage its connection can reconnect or disconnect it",
    );
  }

  async #backchannel(request: Request): Promise<Response> {
    const refuse = (description: string) =>
      errorResponse(request, 400, "invalid_request", description, [], true);
    const client = await this.#client(request);

    if (!client) return refuse("this app has not shaken hands with masks");

    const token = (await readForm(request)).get("logout_token");

    if (!token) return refuse("logout_token is required");

    let logout: LogoutToken;

    try {
      logout = await client.logoutToken(token);
    } catch (error) {
      if (error instanceof InvalidTokenError) return refuse(error.message);

      throw error;
    }

    const accepted = await acceptLogout(
      this.#store,
      this.issuerURL,
      logout,
      Number(this.#options.session?.maxAge) || 30 * 24 * 3600,
    );

    if (!accepted) return refuse("that logout token has already been used");
    await this.#options.onLogout?.(logout, request);

    return new Response(null, {
      status: 200,
      headers: { "cache-control": "no-store" },
    });
  }

  async #configured(request: Request): Promise<boolean> {
    return !!(await this.#credentials.read(request))?.client_id;
  }

  async #client(request?: Request): Promise<Client | undefined> {
    const held = await this.#credentials.read(await this.#requestFor(request));

    if (!held?.client_id) return undefined;

    return (await this.#issuer()).client(held);
  }

  async #revoke(refreshToken: string): Promise<void> {
    try {
      await (await this.#client())?.revoke(refreshToken, "refresh_token");
    } catch {}
  }

  async #disconnected(): Promise<void> {
    try {
      await this.#credentials.clear?.(await this.#requestFor());
    } catch {}
  }

  async #requestFor(request?: Request): Promise<Request> {
    return request ?? new Request(await this.#origin());
  }

  #issuer(): Promise<Issuer> {
    return this.#issuers.get(this.issuerURL);
  }

  #logoutReturnURL(request: Request): string {
    return `${this.#appOrigin(request)}${this.logoutPath}/return`;
  }

  #appOrigin(request: Request): string {
    const origin = new URL(request.url).origin;

    return originOf(this.#resource() ?? origin) ?? origin;
  }

  #delegationReturn(request: Request): string | undefined {
    const path = this.#options.delegations;

    if (!path) return undefined;

    return `${this.#appOrigin(request)}${localPath(path) ?? "/"}`;
  }

  #resource(): string | undefined {
    const env = processEnv();
    const named = this.#options.resource ?? env.MASKS_RESOURCE;

    if (named) return named;

    const url = env.AUTH_URL ?? env.NEXTAUTH_URL;

    return url ? originOf(url) : undefined;
  }

  async #origin(): Promise<string> {
    const resource = this.#resource();
    const named = resource && originOf(resource);

    if (named) return named;

    try {
      const held = await (await nextHeaders()).headers();
      const host = held.get("x-forwarded-host") ?? held.get("host");
      const proto =
        held.get("x-forwarded-proto") ??
        (host?.startsWith("localhost") ? "http" : "https");

      if (host) return `${proto}://${host}`;
    } catch {}

    return "http://localhost";
  }

  #bound(): NextAuthResult {
    if (!this.#result) {
      throw new Error(
        "masks: build Auth.js with masksAuth(NextAuth, options) so masks can reach it",
      );
    }

    return this.#result;
  }
}

function heldOf(value: unknown): HeldSignIn | undefined {
  if (!value || typeof value !== "object") return undefined;

  const held = value as HeldSignIn;

  return typeof held.iss === "string" &&
    typeof held.sub === "string" &&
    typeof held.access_token === "string"
    ? held
    : undefined;
}

function trim(path: string): string {
  return `/${path.replace(/^\/+|\/+$/g, "")}`;
}

function secure(request: Request): boolean {
  return new URL(request.url).protocol === "https:";
}

function hostCookie(request: Request, name: string): string {
  return secure(request) ? `__Host-${name}` : name;
}

function lackingScopes(masked: Masked, wanted: Privilege[]): string[] {
  return wanted
    .filter(
      (privilege) =>
        !privilege.scopes.every((scope) => masked.scopes.includes(scope)),
    )
    .map((privilege) => privilege.name);
}

function askedBefore(stepped: string | undefined, names: string[]): boolean {
  if (!stepped) return false;

  const held = decode(stepped);

  return names.every((name) => held.includes(name));
}

function callbackFrom(request: Request): string | undefined {
  const cookies = parseCookies(request.headers.get("cookie"));
  const held =
    cookies.get("__Secure-authjs.callback-url") ??
    cookies.get("authjs.callback-url");

  if (!held) return undefined;

  try {
    const parsed = new URL(decodeURIComponent(held), request.url);

    if (parsed.origin !== new URL(request.url).origin) return undefined;

    return localPath(`${parsed.pathname}${parsed.search}`);
  } catch {
    return undefined;
  }
}

function payloadOf(token: unknown): Record<string, unknown> {
  if (typeof token !== "string") return {};

  try {
    return decodeJwt(token);
  } catch {
    return {};
  }
}

function decode(value: string): string[] {
  try {
    return decodeURIComponent(value).split(" ");
  } catch {
    return [];
  }
}

function lazy<T>(load: () => Promise<T>): () => Promise<T> {
  let held: Promise<T> | undefined;

  return () => {
    held ??= load();
    return held;
  };
}

const nextHeaders = lazy(() => import("next/headers"));
const nextNavigation = lazy(() => import("next/navigation"));
const nextServer = lazy(() => import("next/server"));
const nextAuthJWT = lazy(() => import("next-auth/jwt"));

export { Masked, type MaskedJSON } from "./app/masked.js";
export { ForbiddenError } from "./claims.js";
export { PATH_HEADER };
