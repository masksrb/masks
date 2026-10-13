import type { Registration } from "../registration.js";
import { processEnv } from "./stores.js";

export interface Credentials
  extends Pick<
    Registration,
    | "client_id"
    | "client_secret"
    | "registration_access_token"
    | "registration_client_uri"
    | "token_endpoint_auth_method"
  > {
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
