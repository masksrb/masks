import { InvalidTokenError } from "./errors.js";
import type { Issuer, Tenant } from "./issuer.js";
import { verifyIssued } from "./jwt.js";

export const BACKCHANNEL_LOGOUT_EVENT =
  "http://schemas.openid.net/event/backchannel-logout";
const LOGOUT_LEEWAY = 60;

export interface IdTokenClaims {
  iss: string;
  sub: string;
  aud: string | string[];
  exp: number;
  iat?: number;
  nonce?: string;
  sid?: string;
  azp?: string;
  auth_time?: number;
  name?: string;
  preferred_username?: string;
  email?: string;
  email_verified?: boolean;
  picture?: string;
  tenant?: Tenant;
  [claim: string]: unknown;
}

export interface LogoutToken {
  iss: string;
  aud: string | string[];
  iat: number;
  exp: number;
  jti: string;
  sub?: string;
  sid?: string;
  events: Record<string, unknown>;
  [claim: string]: unknown;
}

export async function verifyIdToken(
  issuer: Issuer,
  token: string,
  clientId: string,
): Promise<IdTokenClaims> {
  const claims = (await verifyIssued(issuer, token, {
    audience: clientId,
    types: ["jwt", undefined],
    required: ["iss", "sub", "aud", "exp"],
  })) as IdTokenClaims;

  const audience = Array.isArray(claims.aud) ? claims.aud : [claims.aud];

  if (audience.length > 1 && claims.azp !== clientId) {
    throw new InvalidTokenError(
      "that id token names several audiences and was not issued to this client",
    );
  }

  return claims;
}

export async function verifyLogoutToken(
  issuer: Issuer,
  token: string,
  clientId: string,
): Promise<LogoutToken> {
  const claims = (await verifyIssued(issuer, token, {
    audience: clientId,
    types: ["logout+jwt"],
    required: ["iss", "aud", "iat", "exp", "jti", "events"],
  })) as LogoutToken;

  if ("nonce" in claims) {
    throw new InvalidTokenError(
      "that logout token carries a nonce, so it is an id token",
    );
  }

  if (!nonEmpty(claims.sub) && !nonEmpty(claims.sid)) {
    throw new InvalidTokenError(
      "that logout token names neither a subject nor a session",
    );
  }

  if (claims.iat > Date.now() / 1000 + LOGOUT_LEEWAY) {
    throw new InvalidTokenError("that logout token was issued in the future");
  }

  const events = claims.events;

  if (
    !events ||
    typeof events !== "object" ||
    Array.isArray(events) ||
    !events[BACKCHANNEL_LOGOUT_EVENT] ||
    typeof events[BACKCHANNEL_LOGOUT_EVENT] !== "object"
  ) {
    throw new InvalidTokenError("that logout token is not about a logout");
  }

  return claims;
}

function nonEmpty(value: unknown): value is string {
  return typeof value === "string" && value !== "";
}
