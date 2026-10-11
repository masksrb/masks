import { encode, random } from "./pkce.js";

export interface DpopKey {
  privateKey: CryptoKey;
  jwk: JsonWebKey;
}

export async function createDpopKey(): Promise<DpopKey> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign", "verify"],
  );
  const exported = await crypto.subtle.exportKey("jwk", pair.publicKey);

  return {
    privateKey: pair.privateKey,
    jwk: { kty: exported.kty, crv: exported.crv, x: exported.x, y: exported.y },
  };
}

const text = (value: unknown) =>
  encode(new TextEncoder().encode(JSON.stringify(value)).buffer as ArrayBuffer);

export async function dpopProof(
  key: DpopKey,
  method: string,
  url: string,
  accessToken?: string,
): Promise<string> {
  const target = new URL(url);
  const header = { typ: "dpop+jwt", alg: "ES256", jwk: key.jwk };
  const payload: Record<string, unknown> = {
    jti: random(32),
    htm: method.toUpperCase(),
    htu: `${target.origin}${target.pathname}`,
    iat: Math.floor(Date.now() / 1000),
  };

  if (accessToken) {
    payload.ath = encode(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(accessToken),
      ),
    );
  }

  const signing = `${text(header)}.${text(payload)}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key.privateKey,
    new TextEncoder().encode(signing),
  );

  return `${signing}.${encode(signature)}`;
}
