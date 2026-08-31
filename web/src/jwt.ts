import { type Claims, MasksError } from "./types.js";

const HASHES: Record<string, string> = {
  RS256: "SHA-256",
  RS384: "SHA-384",
  RS512: "SHA-512",
};

const ALGORITHM = "RSASSA-PKCS1-v1_5";

export interface Jwk extends JsonWebKey {
  kid?: string;
}

export interface VerifyOptions {
  issuer: string;
  audience: string;
  nonce: string;
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

function json(part: string): Record<string, unknown> {
  try {
    return JSON.parse(new TextDecoder().decode(bytes(part)));
  } catch {
    throw new MasksError("invalid_token", "the id token is not a JWT");
  }
}

function audiences(value: unknown): string[] {
  if (Array.isArray(value)) return value.map(String);

  return value === undefined || value === null ? [] : [String(value)];
}

export async function verifyIdToken(
  token: string,
  { issuer, audience, nonce, keyFor, leeway = 60 }: VerifyOptions,
): Promise<Claims> {
  const [rawHeader, rawPayload, rawSignature, ...rest] = token.split(".");

  if (!rawHeader || !rawPayload || !rawSignature || rest.length > 0) {
    throw new MasksError("invalid_token", "the id token is not a JWT");
  }

  const header = json(rawHeader);
  const hash = HASHES[String(header.alg)];

  if (!hash) {
    throw new MasksError(
      "invalid_token",
      `the id token is signed with ${header.alg}, which this client cannot verify`,
    );
  }

  const key = await crypto.subtle.importKey(
    "jwk",
    { ...(await keyFor(String(header.kid))), alg: String(header.alg) },
    { name: ALGORITHM, hash },
    false,
    ["verify"],
  );

  const signed = await crypto.subtle.verify(
    ALGORITHM,
    key,
    bytes(rawSignature),
    new TextEncoder().encode(`${rawHeader}.${rawPayload}`),
  );

  if (!signed) {
    throw new MasksError(
      "invalid_token",
      "the id token signature does not verify",
    );
  }

  const claims = json(rawPayload) as Claims;
  const now = Math.floor(Date.now() / 1000);

  if (String(claims.iss ?? "").replace(/\/$/, "") !== issuer) {
    throw new MasksError(
      "invalid_token",
      `the id token was issued by ${claims.iss}`,
    );
  }

  if (!audiences(claims.aud).includes(audience)) {
    throw new MasksError(
      "invalid_token",
      "the id token was issued for another client",
    );
  }

  if (typeof claims.exp === "number" && now - leeway >= claims.exp) {
    throw new MasksError("invalid_token", "the id token has expired");
  }

  if (typeof claims.iat === "number" && claims.iat - leeway > now) {
    throw new MasksError(
      "invalid_token",
      "the id token was issued in the future",
    );
  }

  if (claims.nonce !== nonce) {
    throw new MasksError(
      "invalid_nonce",
      "the id token was issued for another request",
    );
  }

  return claims;
}
