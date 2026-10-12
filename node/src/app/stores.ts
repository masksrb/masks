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

export function memoryStore(): SessionStore {
  const held = new Map<string, { data: unknown; until: number }>();

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

  return {
    record(key, at, expiresIn) {
      const now = Date.now();

      for (const [name, found] of held) {
        if (found.until < now) held.delete(name);
      }

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

export function envCredentials(
  env: Record<string, string | undefined> = processEnv(),
): CredentialStore {
  return {
    read() {
      const id = env.MASKS_CLIENT_ID;

      return id
        ? { client_id: id, client_secret: env.MASKS_CLIENT_SECRET || undefined }
        : undefined;
    },
  };
}

export function fileCredentials(path = "masks.json"): CredentialStore {
  let cached: Credentials | null | undefined;

  const fs = async () => import("node:fs/promises");

  return {
    async read() {
      if (cached !== undefined) return cached ?? undefined;

      try {
        const parsed = JSON.parse(await (await fs()).readFile(path, "utf8"));

        cached =
          parsed && typeof parsed.client_id === "string" && parsed.client_id
            ? (parsed as Credentials)
            : null;
      } catch (error) {
        if (
          (error as { code?: string })?.code !== "ENOENT" &&
          !(error instanceof SyntaxError)
        ) {
          throw error;
        }

        cached = null;
      }

      return cached ?? undefined;
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

      cached = held;
    },
    async clear() {
      await (await fs()).rm(path, { force: true });
      cached = null;
    },
  };
}

export function processEnv(): Record<string, string | undefined> {
  return (
    (globalThis as { process?: { env?: Record<string, string | undefined> } })
      .process?.env ?? {}
  );
}
