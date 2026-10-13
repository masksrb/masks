import type { ReplayStore } from "../replay.js";

export interface Store {
  add(
    key: string,
    value: string,
    expiresIn: number,
  ): boolean | Promise<boolean>;
  get(key: string): string | undefined | Promise<string | undefined>;
  set(key: string, value: string, expiresIn: number): void | Promise<void>;
  delete(key: string): void | Promise<void>;
}

const SWEEP_EVERY = 60_000;

export function memoryStore(): Store {
  const held = new Map<string, { value: string; until: number }>();
  let swept = Date.now();

  const sweep = () => {
    const now = Date.now();

    if (now - swept < SWEEP_EVERY) return;

    swept = now;

    for (const [key, found] of held) {
      if (found.until <= now) held.delete(key);
    }
  };

  const live = (key: string) => {
    const found = held.get(key);

    if (!found) return undefined;
    if (found.until > Date.now()) return found;

    held.delete(key);

    return undefined;
  };

  return {
    add(key, value, expiresIn) {
      sweep();

      if (live(key)) return false;

      held.set(key, { value, until: Date.now() + expiresIn * 1000 });

      return true;
    },
    get: (key) => live(key)?.value,
    set(key, value, expiresIn) {
      sweep();
      held.set(key, { value, until: Date.now() + expiresIn * 1000 });
    },
    delete(key) {
      held.delete(key);
    },
  };
}

export function replayStore(store: Store): ReplayStore {
  return {
    first: async (key, expiresIn) =>
      (await store.add(await keyed("proof", key), "1", expiresIn)) === true,
  };
}

export async function keyed(...parts: string[]): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(parts.join("\u0000")),
  );

  return `masks:${[...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")}`;
}

export function remember<K, V>(
  held: Map<K, V>,
  key: K,
  value: V,
  limit: number,
): void {
  held.delete(key);

  for (const oldest of held.keys()) {
    if (held.size < limit) break;
    held.delete(oldest);
  }

  held.set(key, value);
}

export function shared<T>(name: string, create: () => T): T {
  const key = Symbol.for(`@masks/server v1 ${name}`);
  const held = globalThis as unknown as Record<symbol, T | undefined>;

  held[key] ??= create();

  return held[key];
}

export function processEnv(): Record<string, string | undefined> {
  return (
    (globalThis as { process?: { env?: Record<string, string | undefined> } })
      .process?.env ?? {}
  );
}
