import { DPOP, proof } from "./dpop.js";
import {
  decoded,
  ForeignError,
  hasCode,
  MasksError,
  refused,
} from "./errors.js";
import type { Issuer } from "./issuer.js";
import { type Key, random } from "./key.js";

export type AuthMethod =
  | "client_secret_basic"
  | "client_secret_post"
  | "private_key_jwt"
  | "none";

export const GRANT_CLIENT_CREDENTIALS = "client_credentials";
export const GRANT_REFRESH_TOKEN = "refresh_token";
export const GRANT_DEVICE_CODE = "urn:ietf:params:oauth:grant-type:device_code";

const ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer";
const ASSERTION_LIFETIME = 60;
const EXPIRY_LEEWAY = 30;

export const timing = { devicePause: 5000 };

export interface TokenRequest {
  scope?: string[];
  resource?: string[];
}

export interface Token {
  access_token: string;
  token_type: string;
  refresh_token?: string;
  id_token?: string;
  scope?: string;
  expires_in?: number;
  expires_at?: number;
}

export interface DeviceAuthorization {
  device_code: string;
  user_code: string;
  verification_uri: string;
  verification_uri_complete?: string;
  expires_in: number;
  interval?: number;
  expires_at: number;
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

  async revoke(token: string, hint?: string): Promise<void> {
    const form = new URLSearchParams({ token });

    if (hint) form.set("token_type_hint", hint);

    await this.#post(this.issuer.endpoint("revocation_endpoint"), form, false);
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

  async #token(form: URLSearchParams, signal?: AbortSignal): Promise<Token> {
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

    if (this.dpop && !bound(held)) {
      throw new MasksError(
        "invalid_dpop_proof",
        "the token endpoint answered with a token that is not held to this key",
      );
    }

    return held;
  }

  async #post<T>(
    endpoint: string,
    form: URLSearchParams,
    proven: boolean,
    signal?: AbortSignal,
  ): Promise<T> {
    for (let attempt = 0; ; attempt++) {
      const response = await this.issuer.fetch(endpoint, {
        method: "POST",
        ...(await this.#request(endpoint, form, proven, this.#nonce)),
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
      headers.dpop = await proof(this.dpop, "POST", endpoint, undefined, nonce);
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
