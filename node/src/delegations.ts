import {
  type AuthorizationStart,
  type Client,
  constantEqual,
  UPSTREAM_ACCESS_TOKEN_TYPE,
} from "./client.js";
import {
  DelegationRefused,
  DelegationUnavailable,
  InvalidToken,
  Refused,
} from "./errors.js";

export { DelegationRefused, DelegationUnavailable } from "./errors.js";

export const DELEGATION_SCOPE = "masks:delegate:";

const REFUSALS = new Set([
  "invalid_grant",
  "insufficient_scope",
  "invalid_target",
  "unauthorized_client",
  "access_denied",
  "login_required",
  "interaction_required",
  "consent_required",
  "invalid_scope",
]);

export interface DelegationStart extends AuthorizationStart {
  provider: string;
}

export interface Connection {
  connection: string;
  provider: string;
  provider_name?: string;
  label?: string;
  subject?: string;
  secret: string;
  account?: string;
}

export interface PendingDelegation {
  verifier: string;
  nonce?: string;
  provider: string;
  redirectURI: string;
  account: string;
  until: number;
}

export function pendingFor(
  started: DelegationStart,
  account: string,
  until: number,
): PendingDelegation {
  return {
    verifier: started.verifier,
    nonce: started.nonce,
    provider: started.provider,
    redirectURI: started.redirectURI,
    account,
    until,
  };
}

export interface Upstream {
  access_token: string;
  expires_at: number;
  scope: string;
  secret: string;
}

export class Delegations {
  readonly client: Client;
  readonly redirectURI: string;

  constructor(client: Client, redirectURI: string) {
    if (!redirectURI) {
      throw new Error(
        "masks: delegations name the redirect URI they come back to",
      );
    }

    this.client = client;
    this.redirectURI = redirectURI;
  }

  async start(asked: {
    provider: string;
    prompt?: string;
    maxAge?: number;
    state?: string;
  }): Promise<DelegationStart> {
    const provider = String(asked?.provider ?? "");

    if (!/^[a-z0-9][a-z0-9_-]*$/i.test(provider)) {
      throw new Error("masks: a delegation names its provider by key");
    }

    const started = await this.client.start({
      redirectURI: this.redirectURI,
      scope: ["openid", "offline_access", `${DELEGATION_SCOPE}${provider}`],
      prompt: asked.prompt,
      maxAge: asked.maxAge,
      state: asked.state,
    });

    return { ...started, provider };
  }

  async finish(
    returned: URLSearchParams | URL | string,
    started: DelegationStart,
  ): Promise<Connection> {
    const params =
      returned instanceof URLSearchParams
        ? returned
        : returned instanceof URL
          ? returned.searchParams
          : new URL(returned, "http://localhost").searchParams;

    const error = params.get("error");

    if (error) {
      throw new DelegationRefused(
        error,
        params.get("error_description") ?? undefined,
      );
    }

    if (!constantEqual(params.get("state") ?? "", started?.state ?? "")) {
      throw DelegationRefused.of("state_mismatch");
    }

    const { token, claims } = await answered(() =>
      this.client.complete(params, started),
    );
    const held = (token.delegations ?? []).find(
      (one) => one?.provider === started.provider,
    );

    if (!held) {
      throw DelegationRefused.of("nothing_connected", started.provider);
    }

    if (!token.refresh_token) {
      throw DelegationRefused.of("no_refresh_for_connection");
    }

    return {
      connection: held.connection,
      provider: held.provider,
      provider_name: held.provider_name,
      label: held.label,
      subject: held.subject,
      secret: token.refresh_token,
      account: claims?.sub,
    };
  }

  async finishFor(
    returned: URLSearchParams,
    state: string,
    pending: PendingDelegation,
    signedIn: string | undefined,
  ): Promise<Connection> {
    if (signedIn !== pending.account) {
      throw new DelegationRefused(
        "access_denied",
        "that connection was started by somebody other than the person signed in",
      );
    }

    const connection = await this.finish(returned, {
      ...pending,
      state,
      url: "",
    });

    if (connection.account && connection.account !== pending.account) {
      throw new DelegationRefused(
        "access_denied",
        "masks connected that provider for another account",
      );
    }

    return connection;
  }

  async token(secret: string, connection: string): Promise<Upstream> {
    const refreshed = await answered(() => this.client.refresh(secret));
    const rotated = refreshed.refresh_token || secret;
    const released = await answered(
      () =>
        this.client.exchange(refreshed.access_token, {
          requestedTokenType: UPSTREAM_ACCESS_TOKEN_TYPE,
          audience: [connection],
        }),
      rotated,
    );

    return {
      access_token: released.access_token,
      expires_at:
        released.expires_at ??
        Math.floor(Date.now() / 1000) + Number(released.expires_in ?? 0),
      scope: released.scope ?? "",
      secret: rotated,
    };
  }
}

async function answered<T>(
  work: () => Promise<T>,
  secret?: string,
): Promise<T> {
  try {
    return await work();
  } catch (error) {
    if (error instanceof Refused) {
      if (error.code === "invalid_client") throw error;

      if (
        !REFUSALS.has(error.code) &&
        (error.code === "temporarily_unavailable" ||
          (error.status ?? 0) >= 500 ||
          error.status === 429)
      ) {
        throw new DelegationUnavailable(
          `masks answered ${error.status ?? "an error"}: ${error.message}`,
          { secret, cause: error },
        );
      }

      throw new DelegationRefused(error.code, error.description, {
        secret,
        cause: error,
      });
    }

    if (error instanceof InvalidToken) {
      throw new DelegationRefused(error.code, error.description, {
        secret,
        cause: error,
      });
    }

    throw new DelegationUnavailable(
      error instanceof Error ? error.message : "masks could not be reached",
      { secret, cause: error },
    );
  }
}
