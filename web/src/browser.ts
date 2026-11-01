import { type DpopKey, dpopProof, forgetDpopKey, heldDpopKey } from "./dpop.js";
import { failure, Insecure, InvalidToken, Refused } from "./errors.js";
import { type Jwk, verifyIdToken } from "./jwt.js";
import { CLIENT_PATH, list } from "./metadata.js";
import { challenge, method, random } from "./pkce.js";
import type {
  AvatarStyle,
  Avatars,
  Claims,
  Discovery,
  Organization,
  Tokens,
} from "./types.js";

const PENDING = "masks:pending";
const SESSION = "masks:session";

export interface BrowserOptions {
  issuer: string;
  clientId?: string;
  redirectUri?: string;
  scope?: string | string[];
  resource?: string | string[];
  organization?: string;
  fetch?: typeof globalThis.fetch;
  storage?: Storage;
  dpop?: boolean;
}

interface Pending {
  state: string;
  nonce: string;
  verifier: string;
  returnTo: string;
  organization?: string;
}

export interface LogoutOptions {
  everywhere?: boolean;
  postLogoutRedirectUri?: string;
}

export interface AuthorizeOptions {
  returnTo?: string;
  prompt?: string;
  organization?: string;
}

export interface BrowserClient {
  ready(): Promise<Claims | null>;
  discover(): Promise<Discovery>;
  authorize(options?: AuthorizeOptions): Promise<void>;
  authorizeUrl(options?: AuthorizeOptions): Promise<string>;
  pending(): boolean;
  callback(
    url?: string,
  ): Promise<{ tokens: Tokens; identity: Claims | null; returnTo: string }>;
  identity(): Claims | null;
  organization(): Organization | null;
  organizations(): Organization[];
  switchOrganization(
    key: string,
    options?: Omit<AuthorizeOptions, "organization">,
  ): Promise<void>;
  avatars(): Avatars | null;
  avatarUrl(
    subject: string,
    options?: { style?: AvatarStyle; size?: number },
  ): Promise<string>;
  photo(subject?: string): Promise<Blob | null>;
  refresh(): Promise<Tokens>;
  freshAccessToken(leeway?: number): Promise<string | null>;
  fetch(url: string, init?: RequestInit): Promise<Response>;
  proof(method: string, url: string): Promise<string | null>;
  accessToken(): string | null;
  tokens(): Tokens | null;
  authorization(): string | null;
  expired(leeway?: number): boolean;
  logout(options?: LogoutOptions): Promise<void>;
}

export function createBrowserClient(options: BrowserOptions): BrowserClient {
  const issuer = options.issuer.replace(/\/$/, "");
  const call = options.fetch ?? globalThis.fetch.bind(globalThis);
  const store = options.storage ?? globalThis.sessionStorage;
  const scope = list(options.scope ?? ["openid", "profile", "email"]);
  const resources = list(options.resource);
  const here = globalThis.location?.origin;
  const clientId = options.clientId ?? (here && `${here}${CLIENT_PATH}`);
  const redirectUri = options.redirectUri ?? (here && `${here}/`);

  if (!globalThis.crypto?.subtle) {
    throw new Insecure(
      "serve the page over https, or from localhost, since the browser hides the cryptography a sign-in needs on any other http page",
    );
  }

  if (!clientId || !redirectUri) {
    throw new Refused(
      "invalid_request",
      "pass clientId and redirectUri when the client runs outside a browser",
    );
  }

  const restored = restore(store);
  let document: Discovery | null = null;
  let held: Tokens | null = restored?.tokens ?? null;
  let claims: Claims | null = restored?.identity ?? null;
  let keys: Record<string, Jwk> | null = null;
  let refreshing: Promise<Tokens> | null = null;
  let dpopKey: Promise<DpopKey> | null = null;

  const proved = async (
    method: string,
    url: string,
    accessToken?: string,
  ): Promise<Record<string, string>> => {
    if (!options.dpop) return {};

    dpopKey ??= heldDpopKey();

    return { DPoP: await dpopProof(await dpopKey, method, url, accessToken) };
  };
  let generation = 0;

  const clear = () => {
    held = null;
    claims = null;
    save();
  };

  const save = () => {
    try {
      if (held) {
        store.setItem(
          SESSION,
          JSON.stringify({ tokens: held, identity: claims }),
        );
      } else store.removeItem(SESSION);
    } catch {}
  };

  const discover = async (): Promise<Discovery> => {
    if (document) return document;

    const response = await call(`${issuer}/.well-known/openid-configuration`, {
      headers: { Accept: "application/json" },
    });

    if (!response.ok) {
      const { code, description } = failure(
        "answered_status",
        issuer,
        response.status,
      );

      throw new Refused(code, description, { status: response.status });
    }

    const found = (await response.json()) as Discovery;

    if (found.issuer?.replace(/\/$/, "") !== issuer) {
      throw Refused.of("names_another", issuer, String(found.issuer));
    }

    document = found;

    return found;
  };

  const fetchKeys = async (
    revalidate: boolean,
  ): Promise<Record<string, Jwk>> => {
    const { jwks_uri } = await discover();

    if (!jwks_uri) {
      throw Refused.of("publishes_nothing", issuer, "jwks_uri");
    }

    const response = await call(jwks_uri, {
      headers: { Accept: "application/json" },
      ...(revalidate ? { cache: "no-cache" as const } : {}),
    });

    if (!response.ok) {
      const { code, description } = failure(
        "answered_status",
        jwks_uri,
        response.status,
      );

      throw new Refused(code, description, { status: response.status });
    }

    const found = (await response.json()) as { keys?: Jwk[] };

    return Object.fromEntries(
      (found.keys ?? [])
        .filter((jwk) => jwk.kid && (!jwk.use || jwk.use === "sig"))
        .map((jwk) => [jwk.kid as string, jwk]),
    );
  };

  const keyFor = async (kid: string, refresh = false): Promise<Jwk> => {
    if (refresh || !keys) keys = await fetchKeys(refresh);

    const found = keys[kid];

    if (found) return found;
    if (!refresh) return keyFor(kid, true);

    throw InvalidToken.of("no_key", issuer, kid);
  };

  const post = async (body: string[][]): Promise<Tokens> => {
    const started = generation;
    const { token_endpoint } = await discover();

    const response = await call(token_endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
        ...(await proved("POST", token_endpoint)),
      },
      body: new URLSearchParams(body).toString(),
    });

    const payload = (await response.json().catch(() => ({}))) as Record<
      string,
      string
    >;

    if (!response.ok) {
      const { code, description } = payload.error
        ? { code: payload.error, description: payload.error_description }
        : failure("answered_status", token_endpoint, response.status);

      throw new Refused(code, description, { status: response.status });
    }

    if (started !== generation) {
      throw new Refused(
        "invalid_grant",
        "the client signed out while this request was in flight",
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
    organization = options.organization,
  }: AuthorizeOptions = {}): Promise<string> => {
    const { authorization_endpoint } = await discover();
    const verifier = random();

    const waiting: Pending = {
      state: random(24),
      nonce: scope.includes("openid") ? random(24) : "",
      verifier,
      returnTo: returnTo ?? `${location.pathname}${location.search}`,
      ...(organization ? { organization } : {}),
    };

    store.setItem(PENDING, JSON.stringify(waiting));

    const query = new URLSearchParams([
      ["response_type", "code"],
      ["client_id", clientId],
      ["redirect_uri", redirectUri],
      ["scope", scope.join(" ")],
      ["state", waiting.state],
      ["code_challenge", await challenge(verifier)],
      ["code_challenge_method", method],
    ]);

    if (waiting.nonce) query.append("nonce", waiting.nonce);

    for (const value of resources) query.append("resource", value);
    if (prompt) query.append("prompt", prompt);
    if (organization) query.append("organization", organization);

    return `${authorization_endpoint}?${query.toString()}`;
  };

  const avatarUrl = async (
    subject: string,
    { style = "identicon", size }: { style?: AvatarStyle; size?: number } = {},
  ): Promise<string> => {
    const { avatar_endpoint, avatar_styles_supported } = await discover();

    if (!avatar_endpoint) {
      throw Refused.of("publishes_nothing", issuer, "avatar_endpoint");
    }

    if (avatar_styles_supported && !avatar_styles_supported.includes(style)) {
      throw Refused.of("no_avatars", issuer, style);
    }

    const base = `${avatar_endpoint}/${encodeURIComponent(subject)}/${style}`;

    return size ? `${base}?size=${size}` : base;
  };

  const expired = (leeway = 30): boolean => {
    if (!held) return true;

    return Date.now() / 1000 + leeway >= held.obtained_at + held.expires_in;
  };

  const renew = async (): Promise<Tokens> => {
    if (!held?.refresh_token) {
      throw Refused.of("no_refresh_token");
    }

    const previous = held.refresh_token;
    const body = [
      ["grant_type", "refresh_token"],
      ["refresh_token", previous],
      ["client_id", clientId],
    ];

    for (const value of resources) body.push(["resource", value]);

    let tokens: Tokens;

    try {
      tokens = await post(body);
    } catch (failure) {
      if ((failure as { code?: string }).code === "invalid_grant") {
        clear();
      }

      throw failure;
    }

    tokens.refresh_token ??= previous;
    save();

    return tokens;
  };

  const refresh = async (): Promise<Tokens> => {
    refreshing ??= renew().finally(() => {
      refreshing = null;
    });

    return await refreshing;
  };

  const revoke = async (token: string): Promise<void> => {
    const { revocation_endpoint } = await discover();

    if (!revocation_endpoint) return;

    await call(revocation_endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams([
        ["token", token],
        ["token_type_hint", "refresh_token"],
        ["client_id", clientId],
      ]).toString(),
    });
  };

  const client: BrowserClient = {
    async ready() {
      const url = new URL(window.location.href);
      const answered =
        url.searchParams.has("code") || url.searchParams.has("error");

      if (!answered || store.getItem(PENDING) === null) return claims;

      const { returnTo } = await client.callback(url.href);

      window.history.replaceState(window.history.state, "", returnTo);

      return claims;
    },

    discover,
    authorizeUrl,
    avatarUrl,

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
        throw new Refused(
          query.get("error") as string,
          query.get("error_description") ?? undefined,
        );
      }

      if (!raw) {
        throw Refused.of("nothing_in_flight");
      }

      const waiting = JSON.parse(raw) as Pending;

      if (query.get("state") !== waiting.state) {
        throw Refused.of("state_mismatch");
      }

      const code = query.get("code");

      if (!code) {
        throw Refused.of("no_callback_code");
      }

      const body = [
        ["grant_type", "authorization_code"],
        ["code", code],
        ["client_id", clientId],
        ["redirect_uri", redirectUri],
        ["code_verifier", waiting.verifier],
      ];

      for (const value of resources) body.push(["resource", value]);

      const tokens = await post(body);

      if (waiting.nonce) {
        if (!tokens.id_token) {
          clear();

          throw InvalidToken.of("no_id_token");
        }

        try {
          claims = await verifyIdToken(tokens.id_token, {
            issuer,
            audience: clientId,
            nonce: waiting.nonce,
            keyFor,
          });
        } catch (failure) {
          clear();

          throw failure;
        }

        const named = claims?.org?.key;

        if (waiting.organization && named && named !== waiting.organization) {
          clear();

          throw InvalidToken.of(
            "id_token_other_organization",
            waiting.organization,
          );
        }
      }

      save();

      return { tokens, identity: claims, returnTo: waiting.returnTo };
    },

    identity() {
      return claims;
    },

    organization() {
      return claims?.org ?? null;
    },

    organizations() {
      return claims?.orgs ?? [];
    },

    async switchOrganization(key, opts = {}) {
      window.location.assign(
        await authorizeUrl({ ...opts, organization: key }),
      );
    },

    avatars() {
      return (claims?.["masks:avatars"] as Avatars | undefined) ?? null;
    },

    async photo(subject = claims?.sub as string | undefined) {
      if (!subject || !held) return null;

      const response = await call(
        await avatarUrl(subject, { style: "photo" }),
        {
          headers: {
            Authorization: `${held.token_type} ${held.access_token}`,
            Accept: "image/*",
          },
        },
      );

      return response.ok ? await response.blob() : null;
    },

    refresh,

    async fetch(url, init = {}) {
      if (held?.refresh_token && expired()) await refresh();

      const access = held?.access_token;
      const headers = new Headers(init.headers);

      if (access && held) {
        headers.set("Authorization", `${held.token_type} ${access}`);

        for (const [name, value] of Object.entries(
          await proved(init.method ?? "GET", url, access),
        )) {
          headers.set(name, value);
        }
      }

      return await call(url, { ...init, headers });
    },

    async proof(method, url) {
      return (await proved(method, url, held?.access_token)).DPoP ?? null;
    },

    async freshAccessToken(leeway = 30) {
      if (held?.refresh_token && expired(leeway)) await refresh();

      return held?.access_token ?? null;
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

    expired,

    async logout({ everywhere = false, postLogoutRedirectUri } = {}) {
      const leaving = held;

      generation += 1;
      refreshing = null;
      dpopKey = null;
      store.removeItem(PENDING);
      clear();

      await Promise.all([
        options.dpop ? forgetDpopKey() : undefined,
        leaving?.refresh_token
          ? revoke(leaving.refresh_token).catch(() => undefined)
          : undefined,
      ]);

      if (!everywhere) return;

      const { end_session_endpoint } = await discover();

      if (!end_session_endpoint) {
        throw Refused.of("publishes_nothing", issuer, "end_session_endpoint");
      }

      const query = new URLSearchParams([["client_id", clientId]]);

      if (leaving?.id_token) query.append("id_token_hint", leaving.id_token);
      if (postLogoutRedirectUri) {
        query.append("post_logout_redirect_uri", postLogoutRedirectUri);
      }

      window.location.assign(`${end_session_endpoint}?${query.toString()}`);
    },
  };

  return client;
}

function restore(
  store: Storage,
): { tokens: Tokens; identity: Claims | null } | null {
  try {
    const raw = store.getItem(SESSION);
    const found = raw ? JSON.parse(raw) : null;

    return found?.tokens?.access_token ? found : null;
  } catch {
    return null;
  }
}
