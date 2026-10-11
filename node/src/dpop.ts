import { base64url, type Key, random } from "./key.js";

export const DPOP = "DPoP";
export const PROOF_TYPE = "dpop+jwt";

export interface ProofClaims {
  jti: string;
  htm: string;
  htu: string;
  iat: number;
  ath?: string;
  nonce?: string;
}

export async function proof(
  key: Key,
  method: string,
  target: string,
  accessToken?: string,
  nonce?: string,
): Promise<string> {
  const claims: ProofClaims = {
    jti: random(),
    htm: method.toUpperCase(),
    htu: withoutQuery(target),
    iat: Math.floor(Date.now() / 1000),
  };

  if (accessToken) claims.ath = await tokenHash(accessToken);
  if (nonce) claims.nonce = nonce;

  return key.sign(PROOF_TYPE, { ...claims }, true);
}

export async function tokenHash(accessToken: string): Promise<string> {
  return base64url(
    await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(accessToken),
    ),
  );
}

export function withoutQuery(target: string): string {
  const held = new URL(target);
  held.search = "";
  held.hash = "";

  return held.toString();
}
