import type { Context, MiddlewareHandler } from "hono";
import { HTTPException } from "hono/http-exception";
import type { ContentfulStatusCode } from "hono/utils/http-status";
import type { Masked } from "./app/masked.js";
import { Masks, type MasksOptions } from "./app/masks.js";
import { processEnv } from "./app/stores.js";

const installed = new WeakMap<Context, Masks>();

declare module "hono" {
  interface ContextVariableMap {
    masked: Masked;
  }
}

export interface MasksHonoOptions extends MasksOptions {
  masks?: Masks;
  session?: boolean;
}

export function masksHono(options: MasksHonoOptions = {}): MiddlewareHandler {
  let built = options.masks;

  return async (context, next) => {
    built ??= new Masks({
      ...options,
      env: { ...processEnv(), ...strings(context.env) },
    });

    const masks = built;
    const answer = await masks.handle(context.req.raw);

    if (answer) return answer;

    installed.set(context, masks);

    if (options.session !== false) {
      const { masked, cookies } = await masks.masked(context.req.raw);

      context.set("masked", masked);
      setCookies(context, cookies);
    }

    await next();
  };
}

export function requireAuth(...privileges: string[]): MiddlewareHandler {
  return async (context, next) => {
    const masks = installed.get(context);

    if (!masks) throw new Error("masks: use masksHono before requireAuth");

    const outcome = await masks.guard(context.req.raw, ...privileges);

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
  for (const cookie of cookies) {
    context.header("Set-Cookie", cookie, { append: true });
  }
}

function strings(bindings: unknown): Record<string, string> {
  if (!bindings || typeof bindings !== "object") return {};

  return Object.fromEntries(
    Object.entries(bindings).filter(
      (entry): entry is [string, string] => typeof entry[1] === "string",
    ),
  );
}

export { Masked } from "./app/masked.js";
export { Masks, type MasksOptions } from "./app/masks.js";
