import type { MiddlewareHandler } from "hono";
import type { Masked } from "./app/masked.js";
import { Masks, type MasksOptions } from "./app/masks.js";

export type MasksVariables = { masked: Masked };
export type MasksEnv = { Variables: MasksVariables };

export interface MasksHonoOptions {
  session?: boolean;
}

export function masksHono(
  options: Masks | MasksOptions = {},
  asked: MasksHonoOptions = {},
): MiddlewareHandler<MasksEnv> & { masks: Masks } {
  const masks = options instanceof Masks ? options : new Masks(options);

  const handler: MiddlewareHandler<MasksEnv> = async (context, next) => {
    const answer = await masks.handle(context.req.raw);

    if (answer) return answer;

    if (asked.session !== false) {
      const { masked, cookies } = await masks.masked(context.req.raw);

      context.set("masked", masked);
      for (const cookie of cookies) {
        context.header("Set-Cookie", cookie, { append: true });
      }
    }

    await next();
  };

  return Object.assign(handler, { masks });
}

export function masked(
  masks: Masks | (MiddlewareHandler<MasksEnv> & { masks: Masks }),
  ...privileges: string[]
): MiddlewareHandler<MasksEnv> {
  const held = masks instanceof Masks ? masks : masks.masks;

  return async (context, next) => {
    const outcome = await held.guard(context.req.raw, ...privileges);

    if (outcome.response) return outcome.response;

    context.set("masked", outcome.masked);
    for (const cookie of outcome.cookies) {
      context.header("Set-Cookie", cookie, { append: true });
    }

    await next();
  };
}

export { Masked } from "./app/masked.js";
export { Masks, type MasksOptions } from "./app/masks.js";
