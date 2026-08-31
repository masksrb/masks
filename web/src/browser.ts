import { type Jwk, verifyIdToken } from "./jwt.js";
import { challenge, method, random } from "./pkce.js";
import {
  type Claims,
  type Discovery,
  MasksError,
  type Tokens,
} from "./types.js";

const PENDING = "masks:pending";

export interface BrowserOptions {
  issuer: string;
  clientId: string;
  redirectUri: string;
  scope?: string | string[];
  resource?: string | string[];
  fetch?: typeof globalThis.fetch;
  storage?: Storage;
}

interface Pending {
  state: string;
  nonce: string;
  verifier: string;
  returnTo: string;
}

export interface BrowserClient {
  discover(): Promise<Discovery>;
  authorize(options?: { returnTo?: string; prompt?: string }): Promise<void>;
  authorizeUrl(options?: {
    returnTo?: string;
    prompt?: string;
  }): Promise<string>;
  pending(): boolean;
  callback(
    url?: string,
  ): Promise<{ tokens: Tokens; identity: Claims | null; returnTo: string }>;
  identity(): Claims | null;
  refresh(): Promise<Tokens>;
  accessToken(): string | null;
  tokens(): Tokens | null;
  authorization(): string | null;
  expired(leeway?: number): boolean;
  logout(): void;
}

function list(value: string | string[] | undefined): string[] {
  if (!value) return [];

  return Array.isArray(value) ? value : value.split(/\s+/).filter(Boolean);
}

export function createBrowserClient(options: BrowserOptions): BrowserClient {
  const issuer = options.issuer.replace(/\/$/, "");
  const call = options.fetch ?? globalThis.fetch.bind(globalThis);
  const store = options.storage ?? globalThis.sessionStorage;
  const scope = list(options.scope ?? ["openid", "profile", "email"]);
  const resources = list(options.resource);

  let document: Discovery | null = null;
  let held: Tokens | null = null;
  let claims: Claims | null = null;
  let keys: Record<string, Jwk> | null = null;

  const discover = async (): Promise<Discovery> => {
    if (document) return document;

    const response = await call(`${issuer}/.well-known/openid-configuration`, {
      headers: { Accept: "application/json" },
    });

    if (!response.ok) {
      throw new MasksError(
        "invalid_issuer",
        `${issuer} answered ${response.status}`,
        response.status,
      );
    }

    const found = (await response.json()) as Discovery;

    if (found.issuer?.replace(/\/$/, "") !== issuer) {
      throw new MasksError(
        "invalid_issuer",
        `${issuer} publishes a document naming ${found.issuer}`,
      );
    }

    document = found;

    return found;
  };

  const fetchKeys = async (): Promise<Record<string, Jwk>> => {
    const { jwks_uri } = await discover();

    if (!jwks_uri) {
      throw new MasksError(
        "invalid_issuer",
        `${issuer} publishes no jwks_uri, so an id token cannot be verified`,
      );
    }

    const response = await call(jwks_uri, {
      headers: { Accept: "application/json" },
    });

    if (!response.ok) {
      throw new MasksError(
        "invalid_issuer",
        `${jwks_uri} answered ${response.status}`,
        response.status,
      );
    }

    const found = (await response.json()) as { keys?: Jwk[] };

    return Object.fromEntries(
      (found.keys ?? [])
        .filter((jwk) => jwk.kid && (!jwk.use || jwk.use === "sig"))
        .map((jwk) => [jwk.kid as string, jwk]),
    );
  };

  const keyFor = async (kid: string, refresh = false): Promise<Jwk> => {
    if (refresh || !keys) keys = await fetchKeys();

    const found = keys[kid];

    if (found) return found;
    if (!refresh) return keyFor(kid, true);

    throw new MasksError("invalid_token", `${issuer} publishes no key ${kid}`);
  };

  const post = async (body: string[][]): Promise<Tokens> => {
    const { token_endpoint } = await discover();

    const response = await call(token_endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: new URLSearchParams(body).toString(),
    });

    const payload = (await response.json().catch(() => ({}))) as Record<
      string,
      string
    >;

    if (!response.ok) {
      throw new MasksError(
        payload.error ?? `http_${response.status}`,
        payload.error_description,
        response.status,
      );
    }

    held = {
      access_token: payload.access_token,
      id_token: payload.id_token,
      refresh_token: payload.refresh_token,
      token_type: payload.token_type ?? "Bearer",
      scope: payload.scope ?? "",
      expires_in: Number(payload.expires_in ?? 0),
      obtained_at: Math.floor(Date.now() / 1000),
    };

    return held;
  };

  const authorizeUrl = async ({
    returnTo,
    prompt,
  }: {
    returnTo?: string;
    prompt?: string;
  } = {}): Promise<string> => {
    const { authorization_endpoint } = await discover();
    const verifier = random();

    const waiting: Pending = {
      state: random(24),
      nonce: scope.includes("openid") ? random(24) : "",
      verifier,
      returnTo: returnTo ?? `${location.pathname}${location.search}`,
    };

    store.setItem(PENDING, JSON.stringify(waiting));

    const query = new URLSearchParams([
      ["response_type", "code"],
      ["client_id", options.clientId],
      ["redirect_uri", options.redirectUri],
      ["scope", scope.join(" ")],
      ["state", waiting.state],
      ["code_challenge", await challenge(verifier)],
      ["code_challenge_method", method],
    ]);

    if (waiting.nonce) query.append("nonce", waiting.nonce);

    for (const value of resources) query.append("resource", value);
    if (prompt) query.append("prompt", prompt);

    return `${authorization_endpoint}?${query.toString()}`;
  };

  return {
    discover,
    authorizeUrl,

    async authorize(opts = {}) {
      window.location.assign(await authorizeUrl(opts));
    },

    pending() {
      return store.getItem(PENDING) !== null;
    },

    async callback(url = window.location.href) {
      const query = new URL(url).searchParams;
      const raw = store.getItem(PENDING);
      store.removeItem(PENDING);

      if (query.get("error")) {
        throw new MasksError(
          query.get("error") as string,
          query.get("error_description") ?? undefined,
        );
      }

      if (!raw) {
        throw new MasksError(
          "invalid_state",
          "this browser has no authorization in flight",
        );
      }

      const waiting = JSON.parse(raw) as Pending;

      if (query.get("state") !== waiting.state) {
        throw new MasksError(
          "invalid_state",
          "the callback did not match this browser",
        );
      }

      const code = query.get("code");

      if (!code) {
        throw new MasksError("invalid_request", "the callback carried no code");
      }

      const body = [
        ["grant_type", "authorization_code"],
        ["code", code],
        ["client_id", options.clientId],
        ["redirect_uri", options.redirectUri],
        ["code_verifier", waiting.verifier],
      ];

      for (const value of resources) body.push(["resource", value]);

      const tokens = await post(body);

      if (waiting.nonce) {
        if (!tokens.id_token) {
          held = null;

          throw new MasksError(
            "invalid_token",
            "an id token was asked for and the issuer returned none",
          );
        }

        try {
          claims = await verifyIdToken(tokens.id_token, {
            issuer,
            audience: options.clientId,
            nonce: waiting.nonce,
            keyFor,
          });
        } catch (failure) {
          held = null;
          claims = null;

          throw failure;
        }
      }

      return { tokens, identity: claims, returnTo: waiting.returnTo };
    },

    identity() {
      return claims;
    },

    async refresh() {
      if (!held?.refresh_token) {
        throw new MasksError("invalid_grant", "no refresh token is held");
      }

      const body = [
        ["grant_type", "refresh_token"],
        ["refresh_token", held.refresh_token],
        ["client_id", options.clientId],
      ];

      for (const value of resources) body.push(["resource", value]);

      return await post(body);
    },

    accessToken() {
      return held?.access_token ?? null;
    },

    tokens() {
      return held;
    },

    authorization() {
      return held ? `${held.token_type} ${held.access_token}` : null;
    },

    expired(leeway = 30) {
      if (!held) return true;

      return Date.now() / 1000 + leeway >= held.obtained_at + held.expires_in;
    },

    logout() {
      held = null;
      claims = null;
      store.removeItem(PENDING);
    },
  };
}
