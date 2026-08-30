import { type Account, MasksError, type Refusal } from "./types.js";

export interface SessionOptions {
  basePath?: string;
  fetch?: typeof globalThis.fetch;
  csrfToken?: () => string | null;
}

export interface SessionClient {
  session(): Promise<Account | null>;
  require(options?: { returnTo?: string }): Promise<Account>;
  login(options?: { returnTo?: string }): void;
  loginUrl(options?: { returnTo?: string }): string;
  logout(): Promise<void>;
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

  const session = async (): Promise<Account | null> => {
    const response = await call(url("/session"), {
      method: "GET",
      credentials: "same-origin",
      headers: { Accept: "application/json" },
    });

    if (response.status === 401) return null;

    if (!response.ok) {
      throw new MasksError(
        "session_failed",
        `the session endpoint answered ${response.status}`,
        response.status,
      );
    }

    return (await response.json()) as Account;
  };

  return {
    session,

    loginUrl,

    login(opts = {}) {
      window.location.assign(loginUrl(opts));
    },

    async require(opts = {}) {
      const account = await session();

      if (account) return account;

      window.location.assign(loginUrl(opts));

      return await new Promise<Account>(() => {});
    },

    async logout() {
      const token = csrf();

      await call(url("/logout"), {
        method: "DELETE",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          ...(token ? { "X-CSRF-Token": token } : {}),
        },
      });
    },
  };
}

export type { Account, Refusal };
