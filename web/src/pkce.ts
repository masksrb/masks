const ALPHABET =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";

export function random(length = 64): string {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);

  let value = "";
  for (const byte of bytes) value += ALPHABET[byte % ALPHABET.length];

  return value;
}

export function encode(bytes: ArrayBuffer): string {
  let binary = "";
  for (const byte of new Uint8Array(bytes)) binary += String.fromCharCode(byte);

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

export async function challenge(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(verifier),
  );

  return encode(digest);
}

export const method = "S256";
