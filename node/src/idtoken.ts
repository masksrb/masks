import { InvalidToken } from "./errors.js";
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
    throw InvalidToken.of("id_token_several_audiences");
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
    throw InvalidToken.of("logout_with_nonce");
  }

  if (!nonEmpty(claims.sub) && !nonEmpty(claims.sid)) {
    throw InvalidToken.of("logout_names_nobody");
  }

  if (claims.iat > Date.now() / 1000 + LOGOUT_LEEWAY) {
    throw InvalidToken.of("issued_in_future");
  }

  const events = claims.events;

  if (
    !events ||
    typeof events !== "object" ||
    Array.isArray(events) ||
    !events[BACKCHANNEL_LOGOUT_EVENT] ||
    typeof events[BACKCHANNEL_LOGOUT_EVENT] !== "object"
  ) {
    throw InvalidToken.of("not_a_logout");
  }

  return claims;
}

function nonEmpty(value: unknown): value is string {
  return typeof value === "string" && value !== "";
}
