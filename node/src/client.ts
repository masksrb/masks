import { organizationKey } from "./claims.js";
import { DPOP, proof } from "./dpop.js";
import {
  decoded,
  ForeignError,
  hasCode,
  MasksError,
  refused,
} from "./errors.js";
import {
  type IdTokenClaims,
  type LogoutToken,
  verifyIdToken,
  verifyLogoutToken,
} from "./idtoken.js";
import type { Issuer, Tenant } from "./issuer.js";
import { base64url, type Key, random } from "./key.js";

export type AuthMethod =
  | "client_secret_basic"
  | "client_secret_post"
  | "private_key_jwt"
  | "none";

export const GRANT_CLIENT_CREDENTIALS = "client_credentials";
export const GRANT_REFRESH_TOKEN = "refresh_token";
export const GRANT_AUTHORIZATION_CODE = "authorization_code";
export const GRANT_DEVICE_CODE = "urn:ietf:params:oauth:grant-type:device_code";
export const GRANT_TOKEN_EXCHANGE =
  "urn:ietf:params:oauth:grant-type:token-exchange";
export const ACCESS_TOKEN_TYPE =
  "urn:ietf:params:oauth:token-type:access_token";
export const ID_TOKEN_TYPE = "urn:ietf:params:oauth:token-type:id_token";
export const UPSTREAM_ACCESS_TOKEN_TYPE =
  "urn:masks:params:oauth:token-type:upstream_access_token";

const ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer";
const ASSERTION_LIFETIME = 60;
const EXPIRY_LEEWAY = 30;

export const timing = { devicePause: 5000 };

export interface TokenRequest {
  scope?: string[];
  resource?: string[];
}

export interface ExchangeRequest extends TokenRequest {
  subjectTokenType?: string;
  actorToken?: string;
  actorTokenType?: string;
  requestedTokenType?: string;
  audience?: string[];
  lifetime?: number;
}

export interface Delegated {
  connection: string;
  provider: string;
  provider_name?: string;
  label?: string;
  subject?: string;
}

export interface Token {
  access_token: string;
  token_type: string;
  issued_token_type?: string;
  refresh_token?: string;
  id_token?: string;
  scope?: string;
  expires_in?: number;
  expires_at?: number;
  delegations?: Delegated[];
}

export interface AuthorizationRequest {
  redirectURI: string;
  scope?: string[];
  resource?: string[];
  prompt?: string;
  maxAge?: number;
  organization?: string;
  state?: string;
  nonce?: string;
}

export interface PendingAuthorization {
  state: string;
  verifier: string;
  nonce?: string;
  redirectURI: string;
  resource?: string[];
}

export interface AuthorizationStart extends PendingAuthorization {
  url: string;
}

export interface SignIn {
  token: Token;
  claims?: IdTokenClaims;
}

export interface EndSession {
  postLogoutRedirectURI?: string;
  state?: string;
  idTokenHint?: string;
}

export type Userinfo = Record<string, unknown> & { sub: string };

export interface DeviceAuthorization {
  device_code: string;
  user_code: string;
  verification_uri: string;
  verification_uri_complete?: string;
  expires_in: number;
  interval?: number;
  expires_at: number;
}

export interface EnrollmentRequest {
  scope: string[];
  name?: string;
  expiresIn?: number;
}

export interface Enrollment {
  initial_access_token: string;
  scope: string;
  expires_in: number;
  expires_at: number;
}

export interface Introspection {
  active: boolean;
  scope?: string;
  client_id?: string;
  username?: string;
  token_type?: string;
  exp?: number;
  iat?: number;
  sub?: string;
  aud?: string | string[];
  iss?: string;
  jti?: string;
  cnf?: { jkt?: string };
  tenant?: Tenant;
  org?: Record<string, unknown>;
  authorization_details?: Record<string, unknown>[];
  [field: string]: unknown;
}

export interface TokenSource {
  token(): Promise<Token>;
}

export interface ClientOptions {
  issuer: Issuer;
  id: string;
  secret?: string;
  method?: AuthMethod;
  key?: Key;
  dpop?: Key;
}

export function valid(token: Token | undefined | null): token is Token {
  if (!token?.access_token) return false;
  if (!token.expires_at) return true;

  return token.expires_at - Date.now() / 1000 > EXPIRY_LEEWAY;
}

export function bound(token: Token | undefined | null): boolean {
  return !!token && token.token_type?.toLowerCase() === DPOP.toLowerCase();
}

export function scopes(token: { scope?: string }): string[] {
  return (token.scope ?? "").split(/\s+/).filter(Boolean);
}

export class Client {
  readonly issuer: Issuer;
  readonly id: string;
  readonly secret?: string;
  readonly key?: Key;
  readonly dpop?: Key;
  readonly #method?: AuthMethod;
  #nonce?: string;

  constructor(options: ClientOptions) {
    if (!options.id) throw new Error("masks: a client needs its client_id");

    this.issuer = options.issuer;
    this.id = options.id;
    this.secret = options.secret;
    this.#method = options.method;
    this.key = options.key;
    this.dpop = options.dpop;
  }

  get method(): AuthMethod {
    if (this.#method) return this.#method;
    if (this.secret) return "client_secret_basic";
    if (this.key) return "private_key_jwt";

    return "none";
  }

  async start(asked: AuthorizationRequest): Promise<AuthorizationStart> {
    if (!asked?.redirectURI) {
      throw new Error("masks: signing in names a redirectURI");
    }

    const scope = asked.scope ?? ["openid", "profile", "email"];
    const state = asked.state ?? random(32);
    const verifier = random(48);
    const nonce = scope.includes("openid")
      ? (asked.nonce ?? random(32))
      : undefined;
    const query = new URLSearchParams({
      response_type: "code",
      client_id: this.id,
      redirect_uri: asked.redirectURI,
      scope: scope.join(" "),
      state,
      code_challenge: await challenge(verifier),
      code_challenge_method: "S256",
    });

    if (nonce) query.set("nonce", nonce);
    for (const resource of asked.resource ?? []) {
      query.append("resource", resource);
    }
    if (asked.prompt) query.set("prompt", asked.prompt);
    if (asked.maxAge !== undefined) {
      query.set("max_age", String(Math.max(0, Math.floor(asked.maxAge))));
    }

    const organization = organizationKey(asked.organization);
    if (organization) query.set("organization", organization);

    const endpoint = new URL(this.issuer.endpoint("authorization_endpoint"));
    for (const [name, value] of query)
      endpoint.searchParams.append(name, value);

    return {
      url: endpoint.toString(),
      state,
      verifier,
      nonce,
      redirectURI: asked.redirectURI,
      resource: asked.resource,
    };
  }

  async complete(
    returned: URLSearchParams | URL | string,
    pending: PendingAuthorization,
  ): Promise<SignIn> {
    const params = returnedParams(returned);
    const error = params.get("error");

    if (error) {
      throw new MasksError(error, params.get("error_description") ?? undefined);
    }

    if (!constantEqual(params.get("state") ?? "", pending?.state ?? "")) {
      throw new MasksError(
        "invalid_state",
        "that sign-in was not started by this browser",
      );
    }

    const named = params.get("iss");

    if (named !== null && named.replace(/\/+$/, "") !== this.issuer.url) {
      throw new MasksError(
        "invalid_issuer",
        `that sign-in came back from ${JSON.stringify(named)}`,
      );
    }

    if (
      named === null &&
      this.issuer.metadata.authorization_response_iss_parameter_supported ===
        true
    ) {
      throw new MasksError(
        "invalid_issuer",
        "that sign-in came back without naming its issuer",
      );
    }

    const code = params.get("code");

    if (!code) {
      throw new MasksError(
        "invalid_request",
        "that sign-in came back without a code",
      );
    }

    const token = await this.authorizationCode(code, pending);

    if (!token.id_token) {
      if (pending.nonce) {
        throw new MasksError(
          "invalid_nonce",
          "the token endpoint answered without an id token",
        );
      }

      return { token };
    }

    const claims = await this.identity(token.id_token);

    if (
      pending.nonce &&
      !constantEqual(String(claims.nonce ?? ""), pending.nonce)
    ) {
      throw new MasksError(
        "invalid_nonce",
        "the id token was issued for another sign-in",
      );
    }

    return { token, claims };
  }

  authorizationCode(
    code: string,
    pending: Pick<
      PendingAuthorization,
      "verifier" | "redirectURI" | "resource"
    >,
  ): Promise<Token> {
    const form = formFor({ resource: pending.resource });
    form.set("grant_type", GRANT_AUTHORIZATION_CODE);
    form.set("code", code);
    form.set("redirect_uri", pending.redirectURI);
    form.set("code_verifier", pending.verifier);

    return this.#token(form);
  }

  identity(idToken: string): Promise<IdTokenClaims> {
    return verifyIdToken(this.issuer, idToken, this.id);
  }

  logoutToken(token: string): Promise<LogoutToken> {
    return verifyLogoutToken(this.issuer, token, this.id);
  }

  async userinfo(token: Token | string): Promise<Userinfo> {
    const held: Token =
      typeof token === "string"
        ? { access_token: token, token_type: "Bearer" }
        : token;
    const endpoint = this.issuer.endpoint("userinfo_endpoint");
    const signed = signedFetch({
      source: { token: async () => held },
      key: this.dpop,
      origins: [endpoint],
      fetch: this.issuer.fetch,
    });
    const answer = await decoded<Userinfo>(
      await signed(endpoint, { headers: { accept: "application/json" } }),
    );

    if (!answer || typeof answer.sub !== "string" || answer.sub === "") {
      throw new MasksError(
        "server_error",
        "the userinfo endpoint answered without a subject",
      );
    }

    return answer;
  }

  endSessionURL(asked: EndSession = {}): string {
    const endpoint = new URL(this.issuer.endpoint("end_session_endpoint"));

    endpoint.searchParams.set("client_id", this.id);
    if (asked.idTokenHint) {
      endpoint.searchParams.set("id_token_hint", asked.idTokenHint);
    }
    if (asked.postLogoutRedirectURI) {
      endpoint.searchParams.set(
        "post_logout_redirect_uri",
        asked.postLogoutRedirectURI,
      );
    }
    if (asked.state) endpoint.searchParams.set("state", asked.state);

    return endpoint.toString();
  }

  clientCredentials(asked: TokenRequest = {}): Promise<Token> {
    const form = formFor(asked);
    form.set("grant_type", GRANT_CLIENT_CREDENTIALS);

    return this.#token(form);
  }

  refresh(refreshToken: string, asked: TokenRequest = {}): Promise<Token> {
    const form = formFor(asked);
    form.set("grant_type", GRANT_REFRESH_TOKEN);
    form.set("refresh_token", refreshToken);

    return this.#token(form);
  }

  async deviceAuthorization(
    asked: TokenRequest = {},
  ): Promise<DeviceAuthorization> {
    const endpoint = this.issuer.endpoint("device_authorization_endpoint");
    const form = formFor(asked);
    form.set("client_id", this.id);

    const held = await this.#post<Omit<DeviceAuthorization, "expires_at">>(
      endpoint,
      form,
      false,
    );

    return {
      ...held,
      expires_at: Math.floor(Date.now() / 1000) + Number(held.expires_in ?? 0),
    };
  }

  async awaitDevice(
    device: DeviceAuthorization,
    options: { signal?: AbortSignal } = {},
  ): Promise<Token> {
    let interval = Math.max(
      Number(device.interval ?? 0) * 1000,
      timing.devicePause,
    );
    const form = new URLSearchParams({
      grant_type: GRANT_DEVICE_CODE,
      device_code: device.device_code,
    });

    for (;;) {
      if (device.expires_at && Date.now() / 1000 > device.expires_at) {
        throw new MasksError(
          "expired_token",
          "the code expired before anyone approved it",
        );
      }

      await pause(interval, options.signal);

      try {
        return await this.#token(form, options.signal);
      } catch (error) {
        if (hasCode(error, "authorization_pending")) continue;

        if (hasCode(error, "slow_down")) {
          interval += timing.devicePause;
          continue;
        }

        throw error;
      }
    }
  }

  async exchange(
    subjectToken: string,
    asked: ExchangeRequest = {},
  ): Promise<Token> {
    if (typeof subjectToken !== "string" || subjectToken === "") {
      throw new Error("masks: an exchange names a subject token");
    }

    const form = formFor(asked);
    form.set("grant_type", GRANT_TOKEN_EXCHANGE);
    form.set("subject_token", subjectToken);
    form.set("subject_token_type", asked.subjectTokenType ?? ACCESS_TOKEN_TYPE);

    if (asked.actorToken) {
      form.set("actor_token", asked.actorToken);
      form.set("actor_token_type", asked.actorTokenType ?? ACCESS_TOKEN_TYPE);
    }

    if (asked.requestedTokenType) {
      form.set("requested_token_type", asked.requestedTokenType);
    }

    for (const audience of asked.audience ?? []) {
      form.append("audience", audience);
    }

    if (asked.lifetime !== undefined) {
      form.set(
        "requested_lifetime",
        String(seconds(asked.lifetime, "lifetime")),
      );
    }

    const upstream = asked.requestedTokenType === UPSTREAM_ACCESS_TOKEN_TYPE;

    const held = await this.#token(form, undefined, upstream);

    if (upstream && held.issued_token_type !== UPSTREAM_ACCESS_TOKEN_TYPE) {
      throw new MasksError(
        "server_error",
        "the token endpoint answered an upstream exchange with another kind of token",
      );
    }

    return held;
  }

  async revoke(token: string, hint?: string): Promise<void> {
    const form = new URLSearchParams({ token });

    if (hint) form.set("token_type_hint", hint);

    await this.#post(this.issuer.endpoint("revocation_endpoint"), form, false);
  }

  async introspect(token: string, hint?: string): Promise<Introspection> {
    if (typeof token !== "string" || token === "") {
      throw new Error("masks: introspection names a token");
    }

    const form = new URLSearchParams({ token });

    if (hint) form.set("token_type_hint", hint);

    const held = await this.#post<Record<string, unknown> | undefined>(
      this.issuer.endpoint("introspection_endpoint"),
      form,
      false,
    );

    if (!held || typeof held !== "object" || held.active !== true) {
      return { active: false };
    }

    if (
      held.iss !== undefined &&
      String(held.iss).replace(/\/+$/, "") !== this.issuer.url
    ) {
      throw new MasksError(
        "invalid_issuer",
        `the introspection endpoint described a token from ${JSON.stringify(held.iss)}`,
      );
    }

    return held as unknown as Introspection;
  }

  async enroll(asked: EnrollmentRequest): Promise<Enrollment> {
    const scope = (asked?.scope ?? []).filter(Boolean);

    if (scope.length === 0) {
      throw new Error("masks: an enrollment names at least one scope");
    }

    const form = new URLSearchParams({ scope: scope.join(" ") });

    if (asked.name) form.set("client_name", asked.name);

    if (asked.expiresIn !== undefined) {
      form.set("expires_in", String(seconds(asked.expiresIn, "expiresIn")));
    }

    const held = await this.#post<Omit<Enrollment, "expires_at">>(
      this.issuer.endpoint("enrollment_endpoint"),
      form,
      false,
    );

    if (
      typeof held?.initial_access_token !== "string" ||
      !held.initial_access_token
    ) {
      throw new MasksError(
        "server_error",
        "the enrollment endpoint answered without an initial access token",
      );
    }

    const expiresIn = Number(held.expires_in ?? 0);

    return {
      initial_access_token: held.initial_access_token,
      scope: typeof held.scope === "string" ? held.scope : "",
      expires_in: expiresIn,
      expires_at: Math.floor(Date.now() / 1000) + expiresIn,
    };
  }

  async unenroll(machineId: string): Promise<void> {
    if (typeof machineId !== "string" || machineId === "") {
      throw new Error("masks: unenrolling names the machine's client_id");
    }

    await this.#send(
      "DELETE",
      `${this.issuer.endpoint("enrollment_endpoint").replace(/\/+$/, "")}/${encodeURIComponent(machineId)}`,
      new URLSearchParams(),
      false,
    );
  }

  credentialsSource(asked: TokenRequest = {}): TokenSource {
    return reuse(undefined, () => this.clientCredentials(asked));
  }

  refreshSource(
    held: Token,
    asked: TokenRequest = {},
    keep?: (token: Token) => void | Promise<void>,
  ): TokenSource {
    let current = held;

    return reuse(held, async () => {
      if (!current?.refresh_token) {
        throw new MasksError(
          "invalid_grant",
          "there is no refresh token to renew this session with",
        );
      }

      const renewed = await this.refresh(current.refresh_token, asked);
      renewed.refresh_token ??= current.refresh_token;

      if (keep) await keep(renewed);

      current = renewed;

      return renewed;
    });
  }

  fetch(source: TokenSource, origins: string[]): typeof fetch {
    return signedFetch({
      source,
      key: this.dpop,
      origins,
      fetch: this.issuer.fetch,
    });
  }

  async #token(
    form: URLSearchParams,
    signal?: AbortSignal,
    unbound = false,
  ): Promise<Token> {
    const held = await this.#post<Token>(
      this.issuer.endpoint("token_endpoint"),
      form,
      true,
      signal,
    );

    if (!held?.access_token) {
      throw new MasksError(
        "server_error",
        "the token endpoint answered without an access token",
      );
    }

    if (held.expires_in && held.expires_in > 0) {
      held.expires_at = Math.floor(Date.now() / 1000) + held.expires_in;
    }

    if (this.dpop && !bound(held) && !unbound) {
      throw new MasksError(
        "invalid_dpop_proof",
        "the token endpoint answered with a token that is not held to this key",
      );
    }

    return held;
  }

  #post<T>(
    endpoint: string,
    form: URLSearchParams,
    proven: boolean,
    signal?: AbortSignal,
  ): Promise<T> {
    return this.#send<T>("POST", endpoint, form, proven, signal);
  }

  async #send<T>(
    method: string,
    endpoint: string,
    form: URLSearchParams,
    proven: boolean,
    signal?: AbortSignal,
  ): Promise<T> {
    for (let attempt = 0; ; attempt++) {
      const response = await this.issuer.fetch(endpoint, {
        method,
        ...(await this.#request(method, endpoint, form, proven, this.#nonce)),
        redirect: "manual",
        signal,
      });

      const wanted = response.headers.get("dpop-nonce");

      if (proven && wanted) this.#nonce = wanted;

      if (
        proven &&
        this.dpop &&
        attempt === 0 &&
        wanted &&
        response.status >= 400
      ) {
        const error = await refused(response);

        if (
          error.code === "use_dpop_nonce" ||
          response.headers.get("www-authenticate")?.includes("use_dpop_nonce")
        ) {
          continue;
        }

        throw error;
      }

      return decoded<T>(response);
    }
  }

  async #request(
    method: string,
    endpoint: string,
    form: URLSearchParams,
    proven: boolean,
    nonce?: string,
  ): Promise<{ headers: Record<string, string>; body: string }> {
    const held = new URLSearchParams(form);
    const headers: Record<string, string> = {
      "content-type": "application/x-www-form-urlencoded",
      accept: "application/json",
    };

    await this.#authenticate(headers, held);

    if (proven && this.dpop) {
      headers.dpop = await proof(this.dpop, method, endpoint, undefined, nonce);
    }

    return { headers, body: held.toString() };
  }

  async #authenticate(
    headers: Record<string, string>,
    form: URLSearchParams,
  ): Promise<void> {
    switch (this.method) {
      case "client_secret_basic":
        headers.authorization = `Basic ${btoa(`${formEscape(this.id)}:${formEscape(this.secret ?? "")}`)}`;
        return;
      case "client_secret_post":
        form.set("client_id", this.id);
        form.set("client_secret", this.secret ?? "");
        return;
      case "private_key_jwt": {
        if (!this.key) {
          throw new Error("masks: private_key_jwt needs the client's key");
        }

        const now = Math.floor(Date.now() / 1000);
        const assertion = await this.key.sign(
          "JWT",
          {
            iss: this.id,
            sub: this.id,
            aud: this.issuer.url,
            jti: random(),
            iat: now,
            exp: now + ASSERTION_LIFETIME,
          },
          false,
        );

        form.set("client_id", this.id);
        form.set("client_assertion_type", ASSERTION_TYPE);
        form.set("client_assertion", assertion);
        return;
      }
      case "none":
        form.set("client_id", this.id);
        return;
      default:
        throw new Error(
          `masks: ${JSON.stringify(this.method)} is not a way a client authenticates`,
        );
    }
  }
}

function formFor(asked: TokenRequest): URLSearchParams {
  const form = new URLSearchParams();

  if (asked.scope?.length) form.set("scope", asked.scope.join(" "));
  for (const resource of asked.resource ?? [])
    form.append("resource", resource);

  return form;
}

function seconds(value: number, name: string): number {
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`masks: ${name} is a whole number of seconds`);
  }

  return value;
}

function returnedParams(
  returned: URLSearchParams | URL | string,
): URLSearchParams {
  if (returned instanceof URLSearchParams) return returned;
  if (returned instanceof URL) return returned.searchParams;

  return returned.includes("?") || /^https?:/.test(returned)
    ? new URL(returned, "http://localhost").searchParams
    : new URLSearchParams(returned);
}

export async function challenge(verifier: string): Promise<string> {
  return base64url(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)),
  );
}

export function constantEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let differs = a.length ^ b.length;

  for (let index = 0; index < Math.max(a.length, b.length); index++) {
    differs |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }

  return differs === 0 && left !== "";
}

function formEscape(value: string): string {
  return new URLSearchParams({ v: value }).toString().slice(2);
}

function pause(milliseconds: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(signal.reason);

    const timer = setTimeout(() => {
      signal?.removeEventListener("abort", stop);
      resolve();
    }, milliseconds);

    const stop = () => {
      clearTimeout(timer);
      reject(signal?.reason);
    };

    signal?.addEventListener("abort", stop, { once: true });
  });
}

export function reuse(
  held: Token | undefined,
  fetch: () => Promise<Token>,
): TokenSource {
  let current = held;
  let pending: Promise<Token> | undefined;

  return {
    token() {
      if (valid(current)) return Promise.resolve(current);

      pending ??= fetch()
        .then((fetched) => {
          current = fetched;
          return fetched;
        })
        .finally(() => {
          pending = undefined;
        });

      return pending;
    },
  };
}

export interface SignedFetchOptions {
  source: TokenSource;
  key?: Key;
  origins: string[];
  fetch?: typeof fetch;
}

export function signedFetch(options: SignedFetchOptions): typeof fetch {
  const allowed = new Set(
    options.origins.map((origin) => new URL(origin).origin),
  );
  const nonces = new Map<string, string>();
  const base = options.fetch ?? globalThis.fetch;

  const signed = async (
    input: string | URL | Request,
    init?: RequestInit,
  ): Promise<Response> => {
    const request = new Request(input, init);
    const origin = new URL(request.url).origin;

    if (!allowed.has(origin)) {
      throw new ForeignError(
        `this fetch holds tokens only for ${[...allowed].join(", ")}`,
      );
    }

    const token = await options.source.token();
    const body =
      request.body === null ? undefined : await request.arrayBuffer();

    const send = async (nonce?: string) => {
      const headers = new Headers(request.headers);

      if (bound(token)) {
        if (!options.key) {
          throw new Error("masks: a DPoP token needs the key it is held to");
        }

        headers.set("authorization", `${DPOP} ${token.access_token}`);
        headers.set(
          "dpop",
          await proof(
            options.key,
            request.method,
            request.url,
            token.access_token,
            nonce,
          ),
        );
      } else {
        headers.set("authorization", `Bearer ${token.access_token}`);
      }

      return base(request.url, {
        method: request.method,
        headers,
        body,
        redirect: "manual",
        signal: request.signal,
      });
    };

    const response = await send(nonces.get(origin));

    if (!bound(token)) return response;

    const wanted = response.headers.get("dpop-nonce");
    if (!wanted) return response;

    nonces.set(origin, wanted);

    if (
      response.status !== 401 ||
      !response.headers.get("www-authenticate")?.includes("use_dpop_nonce")
    ) {
      return response;
    }

    await response.body?.cancel();

    return send(wanted);
  };

  return signed as typeof fetch;
}
