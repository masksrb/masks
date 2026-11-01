import {
  decodeProtectedHeader,
  errors,
  type JWTPayload,
  jwtVerify,
  type ProtectedHeaderParameters,
} from "jose";
import { InvalidToken, saying, Unavailable } from "./errors.js";
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
    throw unverified(error, issuer, { token });
  }

  const typ = typed(verified.protectedHeader.typ);

  if (!expected.types.includes(typ)) {
    throw InvalidToken.of(
      "wrong_type",
      verified.protectedHeader.typ ?? "nothing",
      expected.types.filter(Boolean).join(" or "),
    );
  }

  return verified.payload;
}

export interface Expecting {
  token?: string;
  typ?: string;
}

export function unverified(
  error: unknown,
  issuer?: Issuer,
  expecting: Expecting = {},
): Error {
  if (error instanceof InvalidToken) return error;

  if (error instanceof errors.JOSEError) {
    return new InvalidToken(described(error, issuer, expecting), {
      cause: error,
    });
  }

  return new Unavailable(
    saying("keys_unreachable", issuer?.url ?? "the issuer"),
    { cause: error },
  );
}

function typed(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;

  return value.toLowerCase().replace(/^application\//, "");
}

function header(token?: string): ProtectedHeaderParameters | undefined {
  if (!token) return undefined;

  try {
    return decodeProtectedHeader(token);
  } catch {
    return undefined;
  }
}

function described(
  error: InstanceType<typeof errors.JOSEError>,
  issuer?: Issuer,
  expecting: Expecting = {},
): string {
  if (error instanceof errors.JWTExpired) return saying("expired");

  if (error instanceof errors.JWTClaimValidationFailed) {
    if (error.reason === "missing") {
      return saying("missing_claims", error.claim);
    }

    switch (error.claim) {
      case "iss":
        return saying("other_issuer");
      case "aud":
        return saying("other_audience");
      case "nbf":
      case "iat":
        return saying("not_valid_yet");
      case "typ":
        return saying(
          "wrong_type",
          header(expecting.token)?.typ ?? "nothing",
          expecting.typ ?? "",
        );
    }

    return saying("unverified");
  }

  if (error instanceof errors.JOSEAlgNotAllowed) {
    return saying(
      "not_an_algorithm",
      header(expecting.token)?.alg ?? "that algorithm",
    );
  }

  if (error instanceof errors.JWSSignatureVerificationFailed) {
    return saying("not_signed_by", issuer?.url ?? "its issuer");
  }

  if (
    error instanceof errors.JWSInvalid ||
    error instanceof errors.JWTInvalid
  ) {
    return saying("not_a_jwt");
  }

  return saying("unverified");
}
