import {
  type AuthorizationStart,
  type Client,
  constantEqual,
  UPSTREAM_ACCESS_TOKEN_TYPE,
} from "./client.js";
import { InvalidTokenError, MasksError } from "./errors.js";

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

export class DelegationRefused extends Error {
  readonly code: string;
  readonly description?: string;
  readonly secret?: string;

  constructor(
    code: string,
    description?: string,
    options: { secret?: string; cause?: unknown } = {},
  ) {
    super(description ? `masks: ${code}: ${description}` : `masks: ${code}`, {
      cause: options.cause,
    });
    this.name = "DelegationRefused";
    this.code = code;
    this.description = description;
    this.secret = options.secret;
  }

  get signedInAgain(): boolean {
    return (
      this.code === "login_required" || this.code === "interaction_required"
    );
  }
}

export class DelegationUnavailable extends Error {
  readonly secret?: string;

  constructor(
    message: string,
    options: { secret?: string; cause?: unknown } = {},
  ) {
    super(`masks: unavailable: ${message}`, { cause: options.cause });
    this.name = "DelegationUnavailable";
    this.secret = options.secret;
  }
}

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
      throw new DelegationRefused(
        "invalid_state",
        "the state did not match the one this connection started with",
      );
    }

    const { token } = await answered(() =>
      this.client.complete(params, started),
    );
    const held = (token.delegations ?? []).find(
      (one) => one?.provider === started.provider,
    );

    if (!held) {
      throw new DelegationRefused(
        "access_denied",
        `masks connected nothing for ${started.provider}`,
      );
    }

    if (!token.refresh_token) {
      throw new DelegationRefused(
        "invalid_grant",
        "masks issued no refresh token to keep the connection with",
      );
    }

    return {
      connection: held.connection,
      provider: held.provider,
      provider_name: held.provider_name,
      label: held.label,
      subject: held.subject,
      secret: token.refresh_token,
    };
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
    if (error instanceof MasksError) {
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

    if (error instanceof InvalidTokenError) {
      throw new DelegationRefused("invalid_token", error.message, {
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
