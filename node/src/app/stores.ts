export interface SessionStore {
  get(id: string): unknown | Promise<unknown>;
  set(id: string, data: unknown, maxAge: number): void | Promise<void>;
  delete(id: string): void | Promise<void>;
}

export interface LogoutStore {
  record(key: string, at: number, expiresIn: number): void | Promise<void>;
  since(key: string): number | undefined | Promise<number | undefined>;
}

export interface Credentials {
  client_id: string;
  client_secret?: string;
  registration_access_token?: string;
  registration_client_uri?: string;
  connected_at?: string;
}

export interface CredentialStore {
  read(
    request: Request,
  ): Credentials | undefined | Promise<Credentials | undefined>;
  write?(request: Request, credentials: Credentials): void | Promise<void>;
  clear?(request: Request): void | Promise<void>;
}

const RECHECK = 1000;

function missing(error: unknown): boolean {
  return (error as { code?: string })?.code === "ENOENT";
}

export interface RefreshStore {
  get(key: string): string | undefined | Promise<string | undefined>;
  set(key: string, value: string, expiresIn: number): void | Promise<void>;
  claim(key: string, expiresIn: number): boolean | Promise<boolean>;
}

const SWEEP_EVERY = 60_000;

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

function sweeper(held: Map<string, { until: number }>): () => void {
  let swept = Date.now();

  return () => {
    const now = Date.now();

    if (now - swept < SWEEP_EVERY) return;

    swept = now;

    for (const [key, found] of held) {
      if (found.until < now) held.delete(key);
    }
  };
}

export function memoryRefreshes(): RefreshStore {
  const held = new Map<string, { value: string; until: number }>();
  const sweep = sweeper(held);
  const live = (key: string) => {
    const found = held.get(key);

    if (found && found.until < Date.now()) held.delete(key);

    return held.get(key);
  };

  return {
    get: (key) => live(key)?.value,
    set(key, value, expiresIn) {
      sweep();
      held.set(key, { value, until: Date.now() + expiresIn * 1000 });
    },
    claim(key, expiresIn) {
      sweep();

      if (live(key)) return false;

      held.set(key, { value: "", until: Date.now() + expiresIn * 1000 });

      return true;
    },
  };
}

export function memoryStore(): SessionStore {
  const held = new Map<string, { data: unknown; until: number }>();
  const sweep = sweeper(held);

  return {
    get(id) {
      const found = held.get(id);

      if (!found) return undefined;
      if (found.until < Date.now()) {
        held.delete(id);
        return undefined;
      }

      return structuredClone(found.data);
    },
    set(id, data, maxAge) {
      sweep();
      held.set(id, {
        data: structuredClone(data),
        until: Date.now() + maxAge * 1000,
      });
    },
    delete(id) {
      held.delete(id);
    },
  };
}

export function memoryLogouts(): LogoutStore {
  const held = new Map<string, { at: number; until: number }>();
  const sweep = sweeper(held);

  return {
    record(key, at, expiresIn) {
      const now = Date.now();

      sweep();

      const before = held.get(key)?.at ?? 0;
      held.set(key, {
        at: Math.max(at, before),
        until: now + expiresIn * 1000,
      });
    },
    since(key) {
      const found = held.get(key);

      return found && found.until >= Date.now() ? found.at : undefined;
    },
  };
}

export function memoryCredentials(initial?: Credentials): CredentialStore {
  let held = initial ? { ...initial } : undefined;

  return {
    read: () => (held ? { ...held } : undefined),
    write: (_request, credentials) => {
      held = { ...credentials };
    },
    clear: () => {
      held = undefined;
    },
  };
}

export function envCredentials({
  prefix = "MASKS_CLIENT",
  env = processEnv(),
}: {
  prefix?: string;
  env?: Record<string, string | undefined>;
} = {}): CredentialStore {
  return {
    read() {
      const id = env[`${prefix}_ID`];

      return id
        ? { client_id: id, client_secret: env[`${prefix}_SECRET`] || undefined }
        : undefined;
    },
  };
}

export function defaultCredentials(
  env: Record<string, string | undefined>,
  ...prefixes: string[]
): CredentialStore {
  const prefix = prefixes.find((named) => env[`${named}_ID`]);

  return prefix ? envCredentials({ prefix, env }) : fileCredentials();
}

export function fileCredentials(path = "masks.json"): CredentialStore {
  let cached:
    | { at: number; checked: number; held: Credentials | undefined }
    | undefined;
  let files: Promise<typeof import("node:fs/promises")> | undefined;

  const fs = () => {
    files ??= import("node:fs/promises");
    return files;
  };

  const changedAt = async (): Promise<number> => {
    try {
      return (await (await fs()).stat(path)).mtimeMs;
    } catch (error) {
      if (missing(error)) return 0;
      throw error;
    }
  };

  return {
    async read() {
      if (cached && Date.now() - cached.checked < RECHECK) return cached.held;

      const at = await changedAt();

      if (cached && cached.at === at) {
        cached.checked = Date.now();
        return cached.held;
      }

      let held: Credentials | undefined;

      try {
        const parsed = JSON.parse(await (await fs()).readFile(path, "utf8"));

        held =
          parsed && typeof parsed.client_id === "string" && parsed.client_id
            ? (parsed as Credentials)
            : undefined;
      } catch (error) {
        if (!missing(error) && !(error instanceof SyntaxError)) throw error;
      }

      cached = { at, checked: Date.now(), held };

      return held;
    },
    async write(_request, credentials) {
      const files = await fs();
      const held = { ...credentials, connected_at: new Date().toISOString() };
      const temporary = `${path}.${crypto.randomUUID()}`;

      await files.writeFile(temporary, `${JSON.stringify(held, null, 2)}\n`, {
        mode: 0o600,
      });
      await files.rename(temporary, path);
      await files.chmod(path, 0o600);

      cached = { at: await changedAt(), checked: Date.now(), held };
    },
    async clear() {
      await (await fs()).rm(path, { force: true });
      cached = { at: 0, checked: Date.now(), held: undefined };
    },
  };
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
