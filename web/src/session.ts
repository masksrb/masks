import {
  type Account,
  MasksError,
  type Refusal,
  type Status,
} from "./types.js";

export interface SessionOptions {
  basePath?: string;
  fetch?: typeof globalThis.fetch;
  csrfToken?: () => string | null;
}

export interface SessionClient {
  session(): Promise<Account | null>;
  status(): Promise<Status>;
  require(options?: { returnTo?: string }): Promise<Account>;
  login(options?: { returnTo?: string }): void;
  loginUrl(options?: { returnTo?: string }): string;
  handshake(): void;
  handshakeUrl(): string;
  logout(options?: { everywhere?: boolean }): Promise<void>;
}

function metaToken(): string | null {
  if (typeof document === "undefined") return null;

  return (
    document
      .querySelector('meta[name="csrf-token"]')
      ?.getAttribute("content") ?? null
  );
}

function here(): string {
  if (typeof window === "undefined") return "/";

  return `${window.location.pathname}${window.location.search}`;
}

export function createSession(options: SessionOptions = {}): SessionClient {
  const base = (options.basePath ?? "/auth").replace(/\/$/, "");
  const call = options.fetch ?? globalThis.fetch.bind(globalThis);
  const csrf = options.csrfToken ?? metaToken;

  const url = (path: string) => `${base}${path}`;

  const loginUrl = ({ returnTo }: { returnTo?: string } = {}) => {
    const target = returnTo ?? here();

    return `${url("")}?return_to=${encodeURIComponent(target)}`;
  };

  const handshakeUrl = () => url("/handshake");

  const status = async (): Promise<Status> => {
    const response = await call(url("/session"), {
      method: "GET",
      credentials: "same-origin",
      headers: { Accept: "application/json" },
    });

    if (response.ok) {
      return {
        state: "signed_in",
        account: (await response.json()) as Account,
      };
    }

    if (response.status === 401) {
      const refusal = (await response.json().catch(() => ({}))) as Refusal;

      if (refusal.error === "handshake_required") {
        return {
          state: "handshake_required",
          handshakeUrl: refusal.handshake_url ?? handshakeUrl(),
        };
      }

      return {
        state: "signed_out",
        loginUrl: refusal.login_url ?? loginUrl(),
      };
    }

    throw new MasksError(
      "session_failed",
      `the session endpoint answered ${response.status}`,
      response.status,
    );
  };

  const session = async (): Promise<Account | null> => {
    const held = await status();

    return held.state === "signed_in" ? held.account : null;
  };

  return {
    session,
    status,
    loginUrl,
    handshakeUrl,

    login(opts = {}) {
      window.location.assign(loginUrl(opts));
    },

    handshake() {
      window.location.assign(handshakeUrl());
    },

    async require(opts = {}) {
      const held = await status();

      if (held.state === "signed_in") return held.account;

      window.location.assign(
        held.state === "handshake_required"
          ? held.handshakeUrl
          : loginUrl(opts),
      );

      return await new Promise<Account>(() => {});
    },

    async logout({ everywhere = false } = {}) {
      const token = csrf();

      const response = await call(
        url(everywhere ? "/logout?everywhere=1" : "/logout"),
        {
          method: "DELETE",
          credentials: "same-origin",
          headers: {
            Accept: "application/json",
            ...(token ? { "X-CSRF-Token": token } : {}),
          },
        },
      );

      if (!everywhere) return;

      const body = (await response.json().catch(() => ({}))) as {
        logout_url?: string;
      };

      if (body.logout_url && typeof window !== "undefined") {
        window.location.assign(body.logout_url);
        await new Promise<void>(() => {});
      }
    },
  };
}

export type { Account, Refusal, Status };
