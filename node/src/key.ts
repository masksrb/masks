import {
  calculateJwkThumbprint,
  exportJWK,
  generateKeyPair,
  importJWK,
  type JWK,
  type JWTPayload,
  SignJWT,
} from "jose";

const ALGORITHM = "ES256";

export interface PrivateJWK extends JWK {
  d: string;
}

export class Key {
  readonly thumbprint: string;
  readonly publicJWK: JWK;
  readonly #private: CryptoKey;
  readonly #jwk: PrivateJWK;

  private constructor(privateKey: CryptoKey, jwk: PrivateJWK, kid: string) {
    this.#private = privateKey;
    this.#jwk = { ...jwk, kid, alg: ALGORITHM, use: "sig" };
    this.thumbprint = kid;
    this.publicJWK = Object.freeze({
      kty: jwk.kty,
      crv: jwk.crv,
      x: jwk.x,
      y: jwk.y,
      kid,
      alg: ALGORITHM,
      use: "sig",
    });
  }

  static async generate(): Promise<Key> {
    const { privateKey } = await generateKeyPair(ALGORITHM, {
      extractable: true,
    });

    return Key.import((await exportJWK(privateKey)) as PrivateJWK);
  }

  static async import(jwk: JWK | string): Promise<Key> {
    const held = (typeof jwk === "string" ? JSON.parse(jwk) : jwk) as JWK;

    if (
      held.kty !== "EC" ||
      held.crv !== "P-256" ||
      typeof held.d !== "string"
    ) {
      throw new Error("masks: a key is a private P-256 key");
    }

    const privateKey = (await importJWK(
      { kty: held.kty, crv: held.crv, x: held.x, y: held.y, d: held.d },
      ALGORITHM,
    )) as CryptoKey;
    const kid = await calculateJwkThumbprint(
      { kty: held.kty, crv: held.crv, x: held.x, y: held.y },
      "sha256",
    );

    return new Key(
      privateKey,
      { kty: held.kty, crv: held.crv, x: held.x, y: held.y, d: held.d },
      kid,
    );
  }

  toJSON(): PrivateJWK {
    return { ...this.#jwk };
  }

  jwks(): { keys: JWK[] } {
    return { keys: [{ ...this.publicJWK }] };
  }

  async sign(typ: string, claims: JWTPayload, embed: boolean): Promise<string> {
    const header = embed
      ? {
          alg: ALGORITHM,
          typ,
          jwk: {
            kty: this.publicJWK.kty,
            crv: this.publicJWK.crv,
            x: this.publicJWK.x,
            y: this.publicJWK.y,
          },
        }
      : { alg: ALGORITHM, typ, kid: this.thumbprint };

    return new SignJWT(claims).setProtectedHeader(header).sign(this.#private);
  }
}

export function random(): string {
  const held = crypto.getRandomValues(new Uint8Array(24));

  return base64url(held);
}

export function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const held = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";

  for (const byte of held) binary += String.fromCharCode(byte);

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}
