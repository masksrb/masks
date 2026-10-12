import type {
  Request as ExpressRequest,
  Response as ExpressResponse,
  NextFunction,
  RequestHandler,
} from "express";
import type { Masked } from "./app/masked.js";
import { Masks, type MasksOptions } from "./app/masks.js";

declare global {
  namespace Express {
    interface Request {
      masked?: Masked;
    }
  }
}

export interface MasksExpressOptions {
  session?: boolean;
}

export function masksExpress(
  options: Masks | MasksOptions = {},
  asked: MasksExpressOptions = {},
): RequestHandler & { masks: Masks } {
  const masks = options instanceof Masks ? options : new Masks(options);

  const handler: RequestHandler = async (request, response, next) => {
    try {
      if (
        masks.owns(
          new URL(request.originalUrl || request.url, "http://localhost")
            .pathname,
        )
      ) {
        const answer = await masks.handle(await toRequest(request, true));

        if (answer) return await send(answer, response);
      }

      const web = await toRequest(request);

      if (asked.session !== false) {
        const { masked, cookies } = await masks.masked(web);

        request.masked = masked;
        for (const cookie of cookies) response.append("Set-Cookie", cookie);
      }

      next();
    } catch (error) {
      next(error);
    }
  };

  return Object.assign(handler, { masks });
}

export function masked(
  masks: Masks | (RequestHandler & { masks: Masks }),
  ...privileges: string[]
): RequestHandler {
  const held = masks instanceof Masks ? masks : masks.masks;

  return async (request, response, next) => {
    try {
      const outcome = await held.guard(await toRequest(request), ...privileges);

      if (outcome.response) return await send(outcome.response, response);

      request.masked = outcome.masked;
      for (const cookie of outcome.cookies) {
        if (!alreadySet(response, cookie))
          response.append("Set-Cookie", cookie);
      }

      next();
    } catch (error) {
      next(error);
    }
  };
}

export async function toRequest(
  request: ExpressRequest,
  withBody = false,
): Promise<Request> {
  const url = new URL(
    request.originalUrl || request.url,
    `${request.protocol}://${request.get("host") ?? "localhost"}`,
  );
  const headers = new Headers();

  for (const [name, value] of Object.entries(request.headers)) {
    if (value === undefined) continue;

    for (const one of Array.isArray(value) ? value : [value]) {
      headers.append(name, one);
    }
  }

  const method = request.method.toUpperCase();

  if (method === "GET" || method === "HEAD" || !withBody) {
    return new Request(url, { method, headers });
  }

  return new Request(url, { method, headers, body: await bodyOf(request) });
}

async function bodyOf(request: ExpressRequest): Promise<string | undefined> {
  const parsed = (request as { body?: unknown }).body;

  if (typeof parsed === "string") return parsed;

  if (parsed && typeof parsed === "object" && !Buffer.isBuffer(parsed)) {
    const type = request.get("content-type") ?? "";

    if (type.includes("application/json")) return JSON.stringify(parsed);

    return new URLSearchParams(
      Object.entries(parsed as Record<string, unknown>).map(([key, value]) => [
        key,
        String(value),
      ]),
    ).toString();
  }

  if (Buffer.isBuffer(parsed)) return parsed.toString("utf8");

  if (!request.readable) return undefined;

  const chunks: Buffer[] = [];
  let size = 0;

  for await (const chunk of request) {
    size += chunk.length;

    if (size > 64 * 1024)
      throw new Error("masks: that request body is too large");

    chunks.push(Buffer.from(chunk));
  }

  return Buffer.concat(chunks).toString("utf8");
}

export async function send(
  answer: Response,
  response: ExpressResponse,
): Promise<void> {
  response.status(answer.status);

  for (const [name, value] of answer.headers) {
    if (name === "set-cookie") continue;

    response.setHeader(name, value);
  }

  for (const cookie of answer.headers.getSetCookie()) {
    if (!alreadySet(response, cookie)) response.append("Set-Cookie", cookie);
  }

  if (!answer.body) {
    response.end();
    return;
  }

  try {
    response.end(Buffer.from(await answer.arrayBuffer()));
  } catch {
    if (!response.headersSent) response.status(502);
    response.end();
  }
}

function alreadySet(response: ExpressResponse, cookie: string): boolean {
  const held = response.getHeader("set-cookie");
  const list = Array.isArray(held) ? held : held ? [String(held)] : [];

  return list.includes(cookie);
}

export { Masked } from "./app/masked.js";
export { Masks, type MasksOptions } from "./app/masks.js";
export type { NextFunction };
