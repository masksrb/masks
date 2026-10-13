import { errors, type JWTPayload, jwtVerify } from "jose";
import { InvalidTokenError, UnavailableError } from "./errors.js";
import type { Issuer } from "./issuer.js";

export const SIGNING_ALGORITHMS = ["RS256", "ES256"];
const LEEWAY = 30;

export interface Expected {
  audience: string | string[];
  types: (string | undefined)[];
  required: string[];
}

export async function verifyIssued(
  issuer: Issuer,
  token: string,
  expected: Expected,
): Promise<JWTPayload> {
  let verified: Awaited<ReturnType<typeof jwtVerify>>;

  try {
    verified = await jwtVerify(
      token,
      async (header) => issuer.key(header.kid),
      {
        algorithms: SIGNING_ALGORITHMS,
        issuer: issuer.url,
        audience: expected.audience,
        requiredClaims: expected.required,
        clockTolerance: LEEWAY,
      },
    );
  } catch (error) {
    throw unverified(error);
  }

  const typ = typed(verified.protectedHeader.typ);

  if (!expected.types.includes(typ)) {
    throw new InvalidTokenError(
      `that token is typed ${JSON.stringify(verified.protectedHeader.typ ?? null)}`,
    );
  }

  return verified.payload;
}

export function unverified(error: unknown): Error {
  if (error instanceof InvalidTokenError) return error;

  if (error instanceof errors.JOSEError) {
    return new InvalidTokenError(described(error), { cause: error });
  }

  return new UnavailableError(
    "the issuer's keys could not be fetched to check that token",
    { cause: error },
  );
}

function typed(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;

  return value.toLowerCase().replace(/^application\//, "");
}

function described(error: InstanceType<typeof errors.JOSEError>): string {
  if (error instanceof errors.JWTExpired) return "that token has expired";

  if (error instanceof errors.JWTClaimValidationFailed) {
    if (error.reason === "missing") {
      return "that token is missing a claim it needs";
    }

    switch (error.claim) {
      case "iss":
        return "that token was issued by another server";
      case "aud":
        return "that token was issued for another app";
      case "nbf":
      case "iat":
        return "that token is not valid yet";
      case "typ":
        return "that token is not typed at+jwt";
    }

    return "that token could not be verified";
  }

  if (error instanceof errors.JOSEAlgNotAllowed) {
    return "that token is signed with an algorithm masks does not use";
  }

  if (error instanceof errors.JWSSignatureVerificationFailed) {
    return "that token was not signed by this issuer";
  }

  if (
    error instanceof errors.JWSInvalid ||
    error instanceof errors.JWTInvalid
  ) {
    return "that token is not a signed JWT";
  }

  return "that token could not be verified";
}
