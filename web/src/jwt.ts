import { InvalidToken } from "./errors.js";
import type { Claims } from "./types.js";

const LEEWAY = 30;
const REQUIRED = ["iss", "sub", "aud", "exp", "iat"];

const ALGORITHMS: Record<
  string,
  {
    importing: RsaHashedImportParams | EcKeyImportParams;
    signing: AlgorithmIdentifier | EcdsaParams;
  }
> = {
  RS256: {
    importing: { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    signing: { name: "RSASSA-PKCS1-v1_5" },
  },
  ES256: {
    importing: { name: "ECDSA", namedCurve: "P-256" },
    signing: { name: "ECDSA", hash: "SHA-256" },
  },
};

export interface Jwk extends JsonWebKey {
  kid?: string;
}

export interface VerifyOptions {
  issuer: string;
  audience: string;
  nonce: string;
  accessToken?: string;
  maxAge?: number;
  leeway?: number;
  keyFor: (kid: string) => Promise<Jwk>;
}

function bytes(part: string): Uint8Array<ArrayBuffer> {
  const padded = part.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(
    padded.padEnd(padded.length + ((4 - (padded.length % 4)) % 4), "="),
  );
  const out = new Uint8Array(new ArrayBuffer(binary.length));

  for (let index = 0; index < binary.length; index++) {
    out[index] = binary.charCodeAt(index);
  }

  return out;
}

function base64url(value: Uint8Array): string {
  return btoa(String.fromCharCode(...value))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function json(part: string): Record<string, unknown> {
  try {
    const held = JSON.parse(new TextDecoder().decode(bytes(part)));

    if (!held || typeof held !== "object" || Array.isArray(held)) {
      throw InvalidToken.of("not_a_jwt");
    }

    return held;
  } catch {
    throw InvalidToken.of("not_a_jwt");
  }
}

function audiences(value: unknown): string[] {
  if (Array.isArray(value)) return value.map(String);

  return value === undefined || value === null ? [] : [String(value)];
}

async function halfHash(value: string): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );

  return base64url(digest.subarray(0, digest.length / 2));
}

export async function verifyIdToken(
  token: string,
  {
    issuer,
    audience,
    nonce,
    accessToken,
    maxAge,
    keyFor,
    leeway = LEEWAY,
  }: VerifyOptions,
): Promise<Claims> {
  const [rawHeader, rawPayload, rawSignature, ...rest] = token.split(".");

  if (
    !rawHeader ||
    !rawPayload ||
    rawSignature === undefined ||
    rest.length > 0
  ) {
    throw InvalidToken.of("not_a_jwt");
  }

  const header = json(rawHeader);
  const algorithm = ALGORITHMS[String(header.alg)];

  if (!algorithm) {
    throw InvalidToken.of("not_an_algorithm", String(header.alg));
  }

  if (header.typ !== undefined) {
    const typ = String(header.typ)
      .toLowerCase()
      .replace(/^application\//, "");

    if (typ !== "jwt") {
      throw InvalidToken.of("wrong_type", String(header.typ), "jwt");
    }
  }

  const key = await crypto.subtle.importKey(
    "jwk",
    { ...(await keyFor(String(header.kid ?? ""))), alg: String(header.alg) },
    algorithm.importing,
    false,
    ["verify"],
  );

  const signed = await crypto.subtle.verify(
    algorithm.signing,
    key,
    bytes(rawSignature),
    new TextEncoder().encode(`${rawHeader}.${rawPayload}`),
  );

  if (!signed) {
    throw InvalidToken.of("not_signed_by", issuer);
  }

  const claims = json(rawPayload) as Claims;
  const now = Math.floor(Date.now() / 1000);

  if (String(claims.iss ?? "").replace(/\/$/, "") !== issuer) {
    throw InvalidToken.of("other_issuer");
  }

  const named = audiences(claims.aud);

  if (!named.includes(audience)) {
    throw InvalidToken.of("other_audience");
  }

  for (const name of REQUIRED) {
    if (claims[name] === undefined) {
      throw InvalidToken.of("missing_claims", name);
    }
  }

  if (typeof claims.exp === "number" && now - leeway >= claims.exp) {
    throw InvalidToken.of("expired");
  }

  if (typeof claims.nbf === "number" && claims.nbf - leeway > now) {
    throw InvalidToken.of("not_valid_yet");
  }

  if (typeof claims.iat === "number" && claims.iat - leeway > now) {
    throw InvalidToken.of("issued_in_future");
  }

  if (named.length > 1 && claims.azp === undefined) {
    throw InvalidToken.of("id_token_several_audiences");
  }

  if (claims.azp !== undefined && claims.azp !== audience) {
    throw InvalidToken.of("id_token_other_client");
  }

  if (claims.nonce !== nonce) {
    throw InvalidToken.of("id_token_other_sign_in");
  }

  if (
    accessToken !== undefined &&
    typeof claims.at_hash === "string" &&
    claims.at_hash !== (await halfHash(accessToken))
  ) {
    throw InvalidToken.of("id_token_other_access_token");
  }

  if (
    maxAge !== undefined &&
    !(
      typeof claims.auth_time === "number" &&
      claims.auth_time + maxAge + leeway >= now
    )
  ) {
    throw InvalidToken.of("too_old");
  }

  return claims;
}
