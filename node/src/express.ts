import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import type { ReadableStream as NodeReadableStream } from "node:stream/web";
import type {
  Request as ExpressRequest,
  Response as ExpressResponse,
  RequestHandler,
} from "express";
import { mergeCookies } from "./app/cookies.js";
import type { Masked } from "./app/masked.js";
import { Masks, type MasksOptions } from "./app/masks.js";

const installed = new WeakMap<
  ExpressRequest,
  { masks: Masks; web: Promise<Request> }
>();

declare global {
  namespace Express {
    interface Request {
      masked?: Masked;
    }
  }
}

export interface MasksExpressOptions extends MasksOptions {
  masks?: Masks;
  session?: boolean;
}

export function masksExpress(
  options: MasksExpressOptions = {},
): RequestHandler & { masks: Masks } {
  const masks = Masks.from(options);

  const handler: RequestHandler = async (request, response, next) => {
    try {
      if (
        masks.owns(
          new URL(request.originalUrl || request.url, "http://localhost")
            .pathname,
        )
      ) {
        const answer = await masks.handle(await toWebRequest(request, true));

        if (answer) return await sendWebResponse(answer, response);
      }

      const web = toWebRequest(request);

      installed.set(request, { masks, web });

      if (options.session !== false) {
        const { masked, cookies } = await masks.masked(await web);

        request.masked = masked;
        setCookies(response, cookies);
      }

      next();
    } catch (error) {
      next(error);
    }
  };

  return Object.assign(handler, { masks });
}

export function requireAuth(...privileges: string[]): RequestHandler {
  return async (request, response, next) => {
    try {
      const held = installed.get(request);

      if (!held) {
        throw new Error("masks: use masksExpress before requireAuth");
      }

      const outcome = await held.masks.guard(await held.web, ...privileges);

      if (outcome.response)
        return await sendWebResponse(outcome.response, response);

      request.masked = outcome.masked;
      setCookies(response, outcome.cookies);

      next();
    } catch (error) {
      next(error);
    }
  };
}

async function toWebRequest(
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

async function sendWebResponse(
  answer: Response,
  response: ExpressResponse,
): Promise<void> {
  response.status(answer.status);

  for (const [name, value] of answer.headers) {
    if (name === "set-cookie") continue;

    response.setHeader(name, value);
  }

  setCookies(response, answer.headers.getSetCookie());

  if (!answer.body) {
    response.end();
    return;
  }

  try {
    await pipeline(
      Readable.fromWeb(answer.body as NodeReadableStream<Uint8Array>),
      response,
    );
  } catch {
    if (!response.headersSent) response.status(502);
    response.destroy();
  }
}

function setCookies(response: ExpressResponse, cookies: string[]): void {
  if (cookies.length === 0) return;

  const held = response.getHeader("set-cookie");

  response.setHeader(
    "Set-Cookie",
    mergeCookies(
      Array.isArray(held) ? held : held ? [String(held)] : [],
      cookies,
    ),
  );
}

export { Masked } from "./app/masked.js";
export { Masks, type MasksOptions } from "./app/masks.js";
