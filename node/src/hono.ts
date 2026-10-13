import type { Context, MiddlewareHandler } from "hono";
import { HTTPException } from "hono/http-exception";
import type { ContentfulStatusCode } from "hono/utils/http-status";
import type { Masked } from "./app/masked.js";
import { Masks, type MasksOptions } from "./app/masks.js";
import { processEnv } from "./app/stores.js";

const installed = new WeakMap<Context, { masks: Masks; sent: Set<string> }>();

declare module "hono" {
  interface ContextVariableMap {
    masked: Masked;
  }
}

export type MasksVariables = { masked: Masked };
export type MasksEnv = { Variables: MasksVariables };

export interface MasksHonoOptions extends MasksOptions {
  masks?: Masks;
  session?: boolean;
}

export function masksHono(
  options: MasksHonoOptions = {},
): MiddlewareHandler & { readonly masks: Masks } {
  let built = options.masks;
  const build = (bindings: unknown) =>
    new Masks({ ...options, env: { ...processEnv(), ...strings(bindings) } });

  const handler: MiddlewareHandler = async (context, next) => {
    built ??= build(context.env);
    const masks = built;
    const answer = await masks.handle(context.req.raw);

    if (answer) return answer;

    installed.set(context, { masks, sent: new Set() });

    if (options.session !== false) {
      const { masked, cookies } = await masks.masked(context.req.raw);

      context.set("masked", masked);
      setCookies(context, cookies);
    }

    await next();
  };

  return Object.defineProperty(handler, "masks", {
    get: () => {
      built ??= build(undefined);
      return built;
    },
  }) as MiddlewareHandler & { readonly masks: Masks };
}

function strings(bindings: unknown): Record<string, string> {
  if (!bindings || typeof bindings !== "object") return {};

  return Object.fromEntries(
    Object.entries(bindings).filter(
      (entry): entry is [string, string] => typeof entry[1] === "string",
    ),
  );
}

export function requireAuth(...privileges: string[]): MiddlewareHandler {
  return async (context, next) => {
    const held = installed.get(context);

    if (!held) throw new Error("masks: use masksHono before requireAuth");

    const outcome = await held.masks.guard(context.req.raw, ...privileges);

    if (outcome.response) {
      throw new HTTPException(outcome.response.status as ContentfulStatusCode, {
        res: outcome.response,
        cause: outcome.error,
      });
    }

    context.set("masked", outcome.masked);
    setCookies(context, outcome.cookies);

    await next();
  };
}

function setCookies(context: Context, cookies: string[]): void {
  const sent = installed.get(context)?.sent;

  for (const cookie of cookies) {
    if (sent?.has(cookie)) continue;

    sent?.add(cookie);
    context.header("Set-Cookie", cookie, { append: true });
  }
}

export { Masked } from "./app/masked.js";
export { Masks, type MasksOptions } from "./app/masks.js";
