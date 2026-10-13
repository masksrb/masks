import { hasCode, rejected } from "../errors.js";
import { base64url, unbase64url } from "../key.js";
import { keyed, type Store, shared } from "./stores.js";

const CLAIM_LIFETIME = 30;
const WAIT_STEP = 50;
const REFRESH_TIMEOUT = 30_000;
const SHORTEST_MEMORY = 60;

export type Renewal<T> =
  | { outcome: "renewed"; value: T }
  | { outcome: "refused" | "unregistered" | "unreachable" };

interface Refresh<T> {
  store: Store;
  issuer: string;
  refreshToken: string;
  refresh: () => Promise<T>;
  expiresAt: (value: T) => number | undefined;
}

const unreachable = { outcome: "unreachable" } as const;

const flights = shared(
  "refreshes",
  () => new Map<string, Promise<Renewal<unknown>>>(),
);

export function renew<T>(asked: Refresh<T>): Promise<Renewal<T>> {
  const key = `${asked.issuer} ${asked.refreshToken}`;
  let held = flights.get(key) as Promise<Renewal<T>> | undefined;

  if (!held) {
    held = across(asked).finally(() => flights.delete(key));
    flights.set(key, held);
  }

  return held;
}

async function across<T>(asked: Refresh<T>): Promise<Renewal<T>> {
  const { store, issuer, refreshToken } = asked;
  const result = await keyed("refreshed", issuer, refreshToken);
  const claim = await keyed("refreshing", issuer, refreshToken);
  const deadline = Date.now() + REFRESH_TIMEOUT;

  try {
    const found = await opened<T>(store, result, refreshToken);

    if (found) return found;

    if (!(await store.add(claim, "1", CLAIM_LIFETIME))) {
      return await awaited<T>(store, result, claim, refreshToken, deadline);
    }
  } catch {
    return unreachable;
  }

  const held = await refreshed(asked);

  if (held.outcome !== "unreachable") {
    try {
      await store.set(
        result,
        await sealed(refreshToken, held),
        memory(held, asked.expiresAt),
      );
    } catch {}
  }

  try {
    await store.delete(claim);
  } catch {}

  return held;
}

async function refreshed<T>(asked: Refresh<T>): Promise<Renewal<T>> {
  try {
    return { outcome: "renewed", value: await asked.refresh() };
  } catch (error) {
    if (hasCode(error, "invalid_client")) return { outcome: "unregistered" };
    if (rejected(error)) return { outcome: "refused" };

    return unreachable;
  }
}

async function awaited<T>(
  store: Store,
  result: string,
  claim: string,
  refreshToken: string,
  deadline: number,
): Promise<Renewal<T>> {
  while (Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, WAIT_STEP));

    const found = await opened<T>(store, result, refreshToken);

    if (found) return found;
    if ((await store.get(claim)) === undefined) return unreachable;
  }

  return unreachable;
}

function memory<T>(
  held: Renewal<T>,
  expiresAt: (value: T) => number | undefined,
): number {
  if (held.outcome !== "renewed") return SHORTEST_MEMORY;

  const left = (expiresAt(held.value) ?? 0) - Math.floor(Date.now() / 1000);

  return Math.max(SHORTEST_MEMORY, left);
}

async function cipher(refreshToken: string): Promise<CryptoKey> {
  const material = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(refreshToken),
    "HKDF",
    false,
    ["deriveKey"],
  );

  return crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: new TextEncoder().encode("masks"),
      info: new TextEncoder().encode("@masks/server shared refresh"),
    },
    material,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

async function sealed<T>(
  refreshToken: string,
  held: Renewal<T>,
): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const closed = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    await cipher(refreshToken),
    new TextEncoder().encode(JSON.stringify(held)),
  );
  const joined = new Uint8Array(iv.byteLength + closed.byteLength);

  joined.set(iv, 0);
  joined.set(new Uint8Array(closed), iv.byteLength);

  return base64url(joined);
}

async function opened<T>(
  store: Store,
  result: string,
  refreshToken: string,
): Promise<Renewal<T> | undefined> {
  const held = await store.get(result);

  if (held === undefined) return undefined;

  try {
    const bytes = unbase64url(held);
    const plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: bytes.slice(0, 12) },
      await cipher(refreshToken),
      bytes.slice(12),
    );
    const found = JSON.parse(new TextDecoder().decode(plain)) as Renewal<T>;

    if (
      found.outcome === "renewed" &&
      found.value &&
      typeof found.value === "object"
    )
      return found;
    if (found.outcome === "refused" || found.outcome === "unregistered")
      return { outcome: found.outcome };
  } catch {}

  return unreachable;
}
