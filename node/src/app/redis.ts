import { bounded } from "../errors.js";
import { check } from "../issuer.js";
import type { Store } from "./stores.js";
import { processEnv } from "./stores.js";

export type RedisCommand = (command: string[]) => Promise<unknown>;

export interface UpstashOptions {
  url?: string;
  token?: string;
  fetch?: typeof fetch;
  allowPlainHTTP?: boolean;
}

export function redisStore(send: RedisCommand): Store {
  return {
    async add(key, value, expiresIn) {
      return (
        text(
          await send(["SET", key, value, "NX", "EX", seconds(expiresIn)]),
        ) === "OK"
      );
    },
    async get(key) {
      return text(await send(["GET", key]));
    },
    async set(key, value, expiresIn) {
      await send(["SET", key, value, "EX", seconds(expiresIn)]);
    },
    async delete(key) {
      await send(["DEL", key]);
    },
  };
}

export function upstashStore(options: UpstashOptions = {}): Store {
  const env = processEnv();
  const url = options.url ?? env.UPSTASH_REDIS_REST_URL ?? env.KV_REST_API_URL;
  const token =
    options.token ?? env.UPSTASH_REDIS_REST_TOKEN ?? env.KV_REST_API_TOKEN;

  if (!url || !token) {
    throw new Error(
      "masks: set UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN, or pass url and token, to reach Upstash",
    );
  }

  check(url, { allowPlainHTTP: options.allowPlainHTTP });

  const base = options.fetch ?? globalThis.fetch;

  return redisStore(async (command) => {
    const answer = await base(url, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(command),
      redirect: "error",
    });
    let parsed: { result?: unknown; error?: unknown };

    try {
      parsed = JSON.parse(await bounded(answer));
    } catch {
      throw new Error(`masks: Upstash answered ${answer.status} without JSON`);
    }

    if (!answer.ok || parsed.error !== undefined) {
      throw new Error(
        `masks: Upstash refused ${command[0]}: ${String(parsed.error ?? answer.status)}`,
      );
    }

    return parsed.result;
  });
}

function seconds(expiresIn: number): string {
  return String(Math.max(1, Math.ceil(expiresIn)));
}

function text(value: unknown): string | undefined {
  if (value === null || value === undefined) return undefined;
  if (typeof value === "string") return value;
  if (value instanceof Uint8Array) return new TextDecoder().decode(value);

  return String(value);
}
