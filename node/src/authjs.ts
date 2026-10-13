import type { NextAuthConfig, NextAuthResult, Session } from "next-auth";
import { parseCookies, serialize } from "./app/cookies.js";
import { Masked, type MaskedJSON } from "./app/masked.js";
import {
  DEFAULT_SCOPE,
  escapeHTML,
  isNetwork,
  json,
  localPath,
  page,
  pick,
  redirect,
  registrationOf,
  sameOrigin,
  text,
  wantsJSON,
} from "./app/masks.js";
import { type PrivilegeSpec, Privileges, unique } from "./app/privileges.js";
import {
  type CredentialStore,
  envCredentials,
  fileCredentials,
  type LogoutStore,
  memoryLogouts,
  processEnv,
  shared,
} from "./app/stores.js";
import { ForbiddenError, organizationKey } from "./claims.js";
import {
  type Client,
  constantEqual,
  scopes as scopesOf,
  type Token,
} from "./client.js";
import { InvalidTokenError, MasksError, UnavailableError } from "./errors.js";
import { Handshake } from "./handshake.js";
import type { LogoutToken } from "./idtoken.js";
import { Issuer } from "./issuer.js";
import { MemoryReplayStore, type ReplayStore } from "./replay.js";

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
  logouts?: LogoutStore;
  replay?: ReplayStore;
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

export interface MasksSession extends Session {
  masks?: MaskedJSON;
}

export interface MasksAuthResult extends NextAuthResult {
  masks: MasksAuth;
  guard: (...privileges: string[]) => Promise<Masked>;
  accessToken: () => Promise<string | undefined>;
  proxy: (request: Request) => Promise<Response>;
}

export const PATH_HEADER = "x-masks-path";

const PREFIX = "/masks";
const HANDSHAKE_COOKIE = "masks-handshake";
const STEPPED_COOKIE = "masks-stepped";
const FLOW_LIFETIME = 3600;
const STEP_UP_WITHIN = 300;
const REFRESH_LEEWAY = 30;
const LOGOUT_MEMORY = 3600;
const DISCOVERY_LIFETIME = 3600_000;
const REMEMBERED_REFRESHES = 10_000;

interface Remembered {
  until: number;
  renewed: Promise<HeldSignIn>;
}

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
  readonly #logouts: LogoutStore;
  readonly #replay: ReplayStore;
  readonly #issuers = shared(
    "authjs issuers",
    () => new Map<string, { at: number; issuer: Promise<Issuer> }>(),
  );
  readonly #refreshes = shared(
    "authjs refreshes",
    () => new Map<string, Remembered>(),
  );
  #result?: NextAuthResult;

  constructor(options: MasksAuthOptions = {}) {
    this.#options = options;
    this.id = options.id ?? "masks";
    this.privileges = new Privileges(options.privileges);
    this.scope = options.scope ?? DEFAULT_SCOPE;
    this.#credentials =
      options.credentials ??
      (processEnv().MASKS_CLIENT_ID ? envCredentials() : fileCredentials());
    this.#logouts =
      options.logouts ?? shared("authjs logouts", () => memoryLogouts());
    this.#replay =
      options.replay ?? shared("authjs replay", () => new MemoryReplayStore());
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
    const named = this.#options.issuer ?? processEnv().MASKS_ISSUER;

    if (!named) {
      throw new Error(
        "masks: set MASKS_ISSUER, or pass issuer, to name the masks server",
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
      guard: (...privileges) => this.guard(...privileges),
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
      try {
        await (await this.#client())?.revoke(
          before.refresh_token,
          "refresh_token",
        );
      } catch {}
    }

    return answer;
  }

  async config(request?: Request): Promise<NextAuthConfig> {
    const options = this.#options;
    const origin = await this.#origin(request);
    const credentials = await this.#credentials.read(
      request ?? new Request(origin ?? "http://localhost"),
    );
    const {
      providers = [],
      callbacks = {},
      events = {},
      session,
      issuer: _issuer,
      resource: _resource,
      name: _name,
      id: _id,
      label: _label,
      scope: _scope,
      namespace: _namespace,
      organization: _organization,
      privileges: _privileges,
      manages: _manages,
      credentials: _credentials,
      logouts: _logouts,
      replay: _replay,
      onLogout: _onLogout,
      allowPlainHTTP: _allowPlainHTTP,
      ...rest
    } = options;

    return {
      ...rest,
      basePath: this.basePath,
      session: { ...session, strategy: "jwt" },
      providers: [
        credentials ? this.#provider(credentials) : this.#unconnected(origin),
        ...providers,
      ],
      callbacks: {
        ...callbacks,
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

          if (held?.refresh_token) {
            try {
              const client = await this.#client();

              await client?.revoke(held.refresh_token, "refresh_token");
            } catch {}
          }

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
        case "POST /logout/backchannel":
          return await this.#backchannel(request);
        default:
          return text(404, "not found", []);
      }
    } catch (error) {
      if (error instanceof MasksError) {
        return refuse(
          request,
          400,
          error.code,
          error.description ?? error.code,
        );
      }

      if (error instanceof UnavailableError || isNetwork(error)) {
        return refuse(
          request,
          503,
          "temporarily_unavailable",
          "masks could not be reached",
        );
      }

      throw error;
    }
  }

  async guard(...names: string[]): Promise<Masked> {
    const { headers, cookies } = await import("next/headers.js");
    const { redirect: navigate } = await import("next/navigation.js");
    const held = await headers();
    const path = localPath(held.get(PATH_HEADER)) ?? "/";
    const session = (await this.#bound().auth()) as MasksSession | null;
    const masked = this.masked(session);

    if (!masked.signedIn) navigate(this.signInPath({ returnTo: path }));

    const wanted = names.map((name) => this.privileges.get(name));
    const missing = wanted.filter((privilege) => !masked.holds(privilege));

    if (missing.length === 0) return masked;

    const lacking = missing.filter(
      (privilege) =>
        !privilege.scopes.every((scope) => masked.scopes.includes(scope)),
    );

    if (lacking.length === 0) {
      masked.member(missing[0] as (typeof missing)[0]);
    }

    const stepped = (await cookies()).get(STEPPED_COOKIE)?.value;
    const asked = lacking.map((privilege) => privilege.name);

    if (stepped && asked.every((name) => decode(stepped).includes(name))) {
      throw new ForbiddenError(
        "insufficient_scope",
        `masks did not grant ${asked.join(", ")}`,
      );
    }

    return navigate(this.signInPath({ returnTo: path, privilege: asked }));
  }

  masked(session: MasksSession | null | undefined): Masked {
    const held = session?.masks;

    if (!held?.signed_in) return Masked.nobody(this.privileges);

    return new Masked({
      signedIn: true,
      privileges: this.privileges,
      scopes: held.scopes,
      expiresAt: held.expires_at,
      accountURL: held.account_url,
      claims: {
        sub: held.subject,
        name: held.name,
        preferred_username: held.nickname,
        email: held.email,
        email_verified: held.email_verified,
        picture: held.picture,
        "masks:avatars": held.avatars,
        tenant: held.tenant,
        org: held.organization,
        orgs: held.organizations,
      },
    });
  }

  async accessToken(): Promise<string | undefined> {
    const { headers } = await import("next/headers.js");
    const held = await headers();
    const signIn = await this.#signInFrom(held);

    if (!signIn) return undefined;

    try {
      return (await this.#fresh(signIn)).access_token;
    } catch {
      return undefined;
    }
  }

  async proxy(request: Request): Promise<Response> {
    const { NextResponse } = await import("next/server.js");
    const url = new URL(request.url);
    const forwarded = new Headers(request.headers);

    forwarded.set(PATH_HEADER, `${url.pathname}${url.search}`);

    const authed = this.#bound().auth as unknown as (
      request: Request,
    ) => Promise<Response>;
    const answered = await authed(request);
    const response = NextResponse.next({ request: { headers: forwarded } });

    for (const cookie of answered.headers.getSetCookie()) {
      response.headers.append("set-cookie", cookie);
    }

    return response;
  }

  async #jwt(params: {
    token: Record<string, unknown>;
    account?: { provider?: string; [key: string]: unknown } | null;
    profile?: Record<string, unknown>;
  }): Promise<Record<string, unknown> | null> {
    const { token, account, profile } = params;

    if (account && account.provider === this.id) {
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
    if (fresh(held) || !held.refresh_token) return token;
    if (!(await this.#client())) return token;

    try {
      return { ...token, masks: await this.#renew(held) };
    } catch (error) {
      if (error instanceof MasksError && error.code === "invalid_client") {
        await this.#disconnected();

        return null;
      }

      if (
        error instanceof MasksError &&
        (error.status ?? 0) < 500 &&
        error.status !== 429
      ) {
        return null;
      }

      return token;
    }
  }

  #signedIn(
    account: Record<string, unknown>,
    profile: Record<string, unknown>,
  ): HeldSignIn {
    const claims = payloadOf(account.id_token);
    const sub = String(profile.sub ?? claims.sub ?? "");
    const now = seconds();

    return {
      iss: this.issuerURL,
      sub,
      sid: typeof claims.sid === "string" ? claims.sid : undefined,
      at: now,
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
  }): MasksSession {
    const { session, token } = params;
    const held = heldOf(token?.masks);

    if (!held) return session;

    const masked = new Masked({
      signedIn: true,
      privileges: this.privileges,
      claims: held.identity,
      scopes: scopesOf(held),
      expiresAt: held.expires_at,
      accountURL: `${held.iss}/`,
    });

    return {
      ...session,
      user: { ...session.user, id: held.sub },
      masks: masked.toJSON(),
    };
  }

  async #departed(held: HeldSignIn): Promise<boolean> {
    if (held.sid) {
      const at = await this.#logouts.since(`${held.iss} sid ${held.sid}`);

      if (at !== undefined && at >= held.at) return true;
    }

    const at = await this.#logouts.since(`${held.iss} sub ${held.sub}`);

    return at !== undefined && at >= held.at;
  }

  async #fresh(held: HeldSignIn): Promise<HeldSignIn> {
    if (fresh(held) || !held.refresh_token) return held;

    return this.#renew(held);
  }

  async #renew(held: HeldSignIn): Promise<HeldSignIn> {
    const key = await digest(`${held.iss} ${held.refresh_token}`);
    const found = this.#refreshes.get(key);

    if (found && found.until > Date.now()) return found.renewed;

    const renewed = this.#refresh(held);
    const remembered: Remembered = {
      until: Date.now() + FLOW_LIFETIME * 1000,
      renewed,
    };

    this.#remember(key, remembered);

    try {
      const answer = await renewed;

      remembered.until =
        Math.max(answer.expires_at ?? 0, seconds() + 60) * 1000;

      return answer;
    } catch (error) {
      if (
        !(error instanceof MasksError) ||
        (error.status ?? 0) >= 500 ||
        error.status === 429
      ) {
        this.#refreshes.delete(key);
      }

      throw error;
    }
  }

  async #refresh(held: HeldSignIn): Promise<HeldSignIn> {
    const client = await this.#client();

    if (!client) {
      throw new UnavailableError("this app is not connected to masks");
    }

    const resource = this.#resource();
    const renewed: Token = await client.refresh(
      held.refresh_token as string,
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
      refresh_token: renewed.refresh_token ?? held.refresh_token,
      expires_at: renewed.expires_at,
      scope: renewed.scope ?? held.scope,
      identity,
    };
  }

  #remember(key: string, remembered: Remembered): void {
    const now = Date.now();

    if (this.#refreshes.size >= REMEMBERED_REFRESHES) {
      for (const [name, found] of this.#refreshes) {
        if (found.until <= now) this.#refreshes.delete(name);
      }
    }

    while (this.#refreshes.size >= REMEMBERED_REFRESHES) {
      const oldest = this.#refreshes.keys().next().value;

      if (oldest === undefined) break;
      this.#refreshes.delete(oldest);
    }

    this.#refreshes.set(key, remembered);
  }

  async #signInFrom(held: Headers): Promise<HeldSignIn | undefined> {
    const { getToken } = await import("next-auth/jwt");
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
        image: new Masked({
          signedIn: true,
          privileges: this.privileges,
          claims: profile,
        }).picture,
      }),
    };
  }

  #unconnected(origin: string | undefined) {
    const target = `${origin ?? "http://localhost"}${this.handshakePath}`;

    return {
      id: this.id,
      name: this.#options.label ?? "masks",
      type: "oauth" as const,
      clientId: "unconnected",
      clientSecret: "unconnected",
      checks: ["state"] as "state"[],
      authorization: { url: target, params: { scope: "openid" } },
      token: target,
      userinfo: target,
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
    const cookies: string[] = [];

    if (privileges.length > 0) {
      const scope = unique([
        ...this.scope,
        ...privileges.flatMap((name) => this.privileges.get(name).scopes),
      ]);

      asked.set("scope", scope.join(" "));
      cookies.push(
        serialize(STEPPED_COOKIE, encodeURIComponent(privileges.join(" ")), {
          secure: secure(request),
          maxAge: STEP_UP_WITHIN,
        }),
      );
    }

    if (organization) asked.set("organization", organization);
    if (prompt === "login" || prompt === "consent") asked.set("prompt", prompt);

    const started = await this.#startSignIn(request, callbackUrl, asked);

    for (const cookie of cookies) started.headers.append("set-cookie", cookie);

    return started;
  }

  async #startSignIn(
    request: Request,
    callbackUrl: string,
    asked: URLSearchParams,
  ): Promise<Response> {
    const result = this.#bound();
    const origin = new URL(request.url).origin;
    const make = request.constructor as typeof Request;
    const jar = parseCookies(request.headers.get("cookie"));
    const written: string[] = [];
    const forwarded = () => {
      const headers = new Headers(request.headers);

      headers.delete("content-type");
      headers.delete("content-length");
      headers.set(
        "cookie",
        [...jar].map(([name, value]) => `${name}=${value}`).join("; "),
      );

      return headers;
    };
    const keep = (response: Response) => {
      for (const line of response.headers.getSetCookie()) {
        written.push(line);

        const [pair = ""] = line.split(";");
        const at = pair.indexOf("=");

        if (at > 0) jar.set(pair.slice(0, at), pair.slice(at + 1));
      }
    };

    const csrf = await result.handlers.GET(
      new make(`${origin}${this.basePath}/csrf`, {
        headers: forwarded(),
      }) as Incoming,
    );

    keep(csrf);

    const { csrfToken } = (await csrf.json()) as { csrfToken?: string };
    const query = asked.toString();
    const headers = forwarded();

    headers.set("content-type", "application/x-www-form-urlencoded");

    const started = await result.handlers.POST(
      new make(
        `${origin}${this.basePath}/signin/${this.id}${query ? `?${query}` : ""}`,
        {
          method: "POST",
          headers,
          body: new URLSearchParams({
            csrfToken: csrfToken ?? "",
            callbackUrl: `${origin}${callbackUrl}`,
          }),
        },
      ) as Incoming,
    );

    keep(started);

    const location = started.headers.get("location");

    if (!location) {
      return refuse(
        request,
        500,
        "signin_failed",
        "Auth.js did not start the sign-in",
      );
    }

    return redirect(location, written, 303);
  }

  async #handshakeShow(request: Request): Promise<Response> {
    if (!(await this.#configured(request)))
      return this.#beginHandshake(request);

    const refused = await this.#manager(request);
    if (refused) return refused;

    const path = escapeHTML(this.handshakePath);

    return page(
      "This app is connected",
      `<p>Reconnecting replaces the credentials it holds with a fresh pair. It is how you rotate them, and how you move this app to another account. No secret passes through your browser.</p>
<p>The app stops working between the approval and the moment it picks the new credentials up.</p>
<form method="post" action="${path}"><button type="submit">Reconnect it</button></form>
${this.#credentials.clear ? `<form method="post" action="${path}/disconnect"><button type="submit">Disconnect it</button></form>` : ""}`,
      [],
    );
  }

  async #handshakeCreate(request: Request): Promise<Response> {
    if (!sameOrigin(request, new URL(request.url).origin)) {
      return refuse(
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
      return refuse(
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
      return refuse(
        request,
        400,
        "invalid_request",
        "the credential store cannot forget this connection",
      );
    }

    const held = await this.#credentials.read(request);

    if (held?.registration_access_token) {
      const issuer = await this.#issuer();

      try {
        await issuer.deleteRegistration(registrationOf(held));
      } catch (error) {
        if (!(error instanceof MasksError) || error.status !== 401) throw error;
      }
    }

    await this.#credentials.clear(request);

    if (wantsJSON(request)) return json(200, { connected: false }, []);

    return redirect("/", [], 303);
  }

  async #handshakeCallback(request: Request): Promise<Response> {
    const params = new URL(request.url).searchParams;
    const state = params.get("state") ?? "";
    const held = parseCookies(request.headers.get("cookie")).get(
      handshakeCookie(request),
    );
    const cleared = serialize(handshakeCookie(request), "", {
      secure: secure(request),
      maxAge: 0,
    });

    if (!held || !state || !constantEqual(held, state)) {
      return refuse(
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
      return refuse(
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
        serialize(handshakeCookie(request), started.state, {
          secure: secure(request),
          maxAge: FLOW_LIFETIME,
        }),
      ],
      303,
    );
  }

  async #handshake(request: Request): Promise<Handshake> {
    const issuer = await this.#issuer();
    const origin = new URL(request.url).origin;
    const resource = this.#resource() ?? origin;
    const base = `${originOf(resource) ?? origin}${this.basePath}`;

    return new Handshake(issuer, {
      name: this.#options.name || new URL(resource).host,
      resource,
      redirectURIs: [`${base}/callback/${this.id}`],
      returnTo: `${base}${PREFIX}/handshake/callback`,
      scope: this.#approvedScope(),
      backchannelLogoutURI: `${base}${PREFIX}/logout/backchannel`,
    });
  }

  #approvedScope(): string[] {
    const asked = unique([...this.scope, ...this.privileges.scopes()]);
    const namespace = this.#options.namespace;

    if (!namespace) return asked;

    return unique([
      ...asked.filter((scope) => !scope.startsWith(namespace)),
      namespace,
    ]);
  }

  async #manager(request: Request): Promise<Response | undefined> {
    const answered = await this.#bound().handlers.GET(
      new (request.constructor as typeof Request)(
        `${new URL(request.url).origin}${this.basePath}/session`,
        { headers: request.headers },
      ) as Incoming,
    );
    const session = answered.ok
      ? ((await answered.json()) as MasksSession | null)
      : null;
    const masked = this.masked(session);
    const written = answered.headers.getSetCookie();

    if (!masked.signedIn) {
      return redirect(
        this.signInPath({ returnTo: this.handshakePath }),
        written,
        303,
      );
    }

    const manages = this.#options.manages;
    let allowed = false;

    if (typeof manages === "string") allowed = masked.privilege(manages);
    else if (typeof manages === "function")
      allowed = (await manages(request, masked)) === true;

    if (allowed) return undefined;

    return refuse(
      request,
      403,
      "forbidden",
      "only somebody this app lets manage its connection can reconnect or disconnect it",
      written,
    );
  }

  async #backchannel(request: Request): Promise<Response> {
    const client = await this.#client(request);

    if (!client) {
      return json(
        400,
        {
          error: "invalid_request",
          error_description: "this app has not shaken hands with masks",
        },
        [],
      );
    }

    const form = new URLSearchParams(await request.text());
    const token = form.get("logout_token");

    if (!token) {
      return json(
        400,
        {
          error: "invalid_request",
          error_description: "logout_token is required",
        },
        [],
      );
    }

    let logout: LogoutToken;

    try {
      logout = await client.logoutToken(token);
    } catch (error) {
      if (error instanceof InvalidTokenError) {
        return json(
          400,
          { error: "invalid_request", error_description: error.message },
          [],
        );
      }

      throw error;
    }

    let first: boolean;

    try {
      first =
        (await this.#replay.first(
          `${this.issuerURL} logout ${logout.jti}`,
          LOGOUT_MEMORY,
        )) === true;
    } catch (error) {
      throw new UnavailableError("the replay store could not be reached", {
        cause: error,
      });
    }

    if (!first) {
      return json(
        400,
        {
          error: "invalid_request",
          error_description: "that logout token has already been used",
        },
        [],
      );
    }

    const at = Math.max(Number(logout.iat) || 0, seconds());
    const lifetime = Number(this.#options.session?.maxAge) || 30 * 24 * 3600;

    if (logout.sid) {
      await this.#logouts.record(
        `${this.issuerURL} sid ${logout.sid}`,
        at,
        lifetime,
      );
    } else if (logout.sub) {
      await this.#logouts.record(
        `${this.issuerURL} sub ${logout.sub}`,
        at,
        lifetime,
      );
    }

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
    const origin = await this.#origin(request);
    const held = await this.#credentials.read(
      request ?? new Request(origin ?? "http://localhost"),
    );

    if (!held?.client_id) return undefined;

    return (await this.#issuer()).client(registrationOf(held));
  }

  async #disconnected(): Promise<void> {
    const origin = await this.#origin();

    try {
      await this.#credentials.clear?.(
        new Request(origin ?? "http://localhost"),
      );
    } catch {}
  }

  async #issuer(): Promise<Issuer> {
    const url = this.issuerURL;
    const found = this.#issuers.get(url);

    if (found && Date.now() - found.at < DISCOVERY_LIFETIME) {
      return found.issuer;
    }

    const issuer = Issuer.discover(url, {
      allowPlainHTTP: this.#options.allowPlainHTTP,
    });

    this.#issuers.set(url, { at: Date.now(), issuer });
    issuer.catch(() => {
      if (this.#issuers.get(url)?.issuer === issuer) this.#issuers.delete(url);
    });

    return issuer;
  }

  #resource(): string | undefined {
    const env = processEnv();
    const named = this.#options.resource ?? env.MASKS_RESOURCE;

    if (named) return named;

    const url = env.AUTH_URL ?? env.NEXTAUTH_URL;

    return url ? originOf(url) : undefined;
  }

  async #origin(request?: Request): Promise<string | undefined> {
    const resource = this.#resource();

    if (resource) return originOf(resource);
    if (request) return new URL(request.url).origin;

    try {
      const { headers } = await import("next/headers.js");
      const held = await headers();
      const host = held.get("x-forwarded-host") ?? held.get("host");
      const proto =
        held.get("x-forwarded-proto") ??
        (host?.startsWith("localhost") ? "http" : "https");

      return host ? `${proto}://${host}` : undefined;
    } catch {
      return undefined;
    }
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

function fresh(held: HeldSignIn): boolean {
  return !held.expires_at || held.expires_at - seconds() > REFRESH_LEEWAY;
}

function seconds(): number {
  return Math.floor(Date.now() / 1000);
}

function trim(path: string): string {
  return `/${path.replace(/^\/+|\/+$/g, "")}`;
}

function originOf(url: string): string | undefined {
  try {
    const parsed = new URL(url);

    return parsed.protocol === "https:" || parsed.protocol === "http:"
      ? parsed.origin
      : undefined;
  } catch {
    return undefined;
  }
}

function secure(request: Request): boolean {
  return new URL(request.url).protocol === "https:";
}

function handshakeCookie(request: Request): string {
  return secure(request) ? `__Host-${HANDSHAKE_COOKIE}` : HANDSHAKE_COOKIE;
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
    const [, body = ""] = token.split(".");
    const parsed = JSON.parse(
      new TextDecoder().decode(
        Uint8Array.from(
          atob(body.replace(/-/g, "+").replace(/_/g, "/")),
          (character) => character.charCodeAt(0),
        ),
      ),
    );

    return parsed && typeof parsed === "object" ? parsed : {};
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

async function digest(value: string): Promise<string> {
  const hashed = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );

  return [...new Uint8Array(hashed)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function refuse(
  request: Request,
  status: number,
  code: string,
  description: string,
  cookies: string[] = [],
): Response {
  if (wantsJSON(request)) {
    return json(
      status,
      { error: code, error_description: description },
      cookies,
    );
  }

  return text(status, `${code}: ${description}`, cookies);
}

export { Masked, type MaskedJSON } from "./app/masked.js";
export { ForbiddenError } from "./claims.js";
