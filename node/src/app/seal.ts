import { base64url, unbase64url } from "../key.js";

const VERSION = "v1";
const MINIMUM = 32;

export class Sealer {
  readonly #secrets: string[];
  readonly #keys = new Map<string, Promise<CryptoKey>>();

  constructor(secrets: string | string[]) {
    const held = (Array.isArray(secrets) ? secrets : [secrets]).filter(
      (secret) => typeof secret === "string" && secret !== "",
    );

    if (held.length === 0) {
      throw new Error(
        "masks: set MASKS_SECRET, or pass secret, to seal sessions (at least 32 characters, such as the output of openssl rand -base64 32)",
      );
    }

    for (const secret of held) {
      if (new TextEncoder().encode(secret).byteLength < MINIMUM) {
        throw new Error("masks: a session secret is at least 32 characters");
      }
    }

    this.#secrets = held;
  }

  async seal(purpose: string, value: unknown): Promise<string> {
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const sealed = await crypto.subtle.encrypt(
      { name: "AES-GCM", iv, additionalData: label(purpose) },
      await this.#key(this.#secrets[0] as string, purpose),
      new TextEncoder().encode(JSON.stringify(value)),
    );
    const joined = new Uint8Array(iv.byteLength + sealed.byteLength);

    joined.set(iv, 0);
    joined.set(new Uint8Array(sealed), iv.byteLength);

    return `${VERSION}.${base64url(joined)}`;
  }

  async unseal<T>(
    purpose: string,
    value: string | undefined,
  ): Promise<T | undefined> {
    if (!value?.startsWith(`${VERSION}.`)) return undefined;

    let bytes: Uint8Array<ArrayBuffer>;

    try {
      bytes = unbase64url(value.slice(VERSION.length + 1));
    } catch {
      return undefined;
    }

    if (bytes.byteLength < 29) return undefined;

    const iv = bytes.slice(0, 12);
    const sealed = bytes.slice(12);

    for (const secret of this.#secrets) {
      try {
        const opened = await crypto.subtle.decrypt(
          { name: "AES-GCM", iv, additionalData: label(purpose) },
          await this.#key(secret, purpose),
          sealed,
        );

        return JSON.parse(new TextDecoder().decode(opened)) as T;
      } catch {}
    }

    return undefined;
  }

  #key(secret: string, purpose: string): Promise<CryptoKey> {
    const id = `${purpose}\u0000${secret}`;
    let held = this.#keys.get(id);

    if (!held) {
      held = derive(secret, purpose);
      this.#keys.set(id, held);
    }

    return held;
  }
}

async function derive(secret: string, purpose: string): Promise<CryptoKey> {
  const material = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    "HKDF",
    false,
    ["deriveKey"],
  );

  return crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: new TextEncoder().encode("masks"),
      info: label(purpose),
    },
    material,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

function label(purpose: string): Uint8Array<ArrayBuffer> {
  return new TextEncoder().encode(`masks/${purpose}`);
}
