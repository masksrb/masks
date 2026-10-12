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
    return new InvalidTokenError(error.message);
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
