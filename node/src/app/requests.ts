import { Refused } from "../errors.js";
import type { Masked } from "./masked.js";

export type PerRequest<T> = T | ((request: Request) => T | Promise<T>);

export const PATH_HEADER = "x-masks-path";

const FORM_LIMIT = 64 * 1024;

export async function resolve<T>(
  value: PerRequest<T> | undefined,
  request: Request,
): Promise<T | undefined> {
  if (typeof value === "function") {
    return (value as (request: Request) => T | Promise<T>)(request);
  }

  return value;
}

export function localPath(
  value: string | null | undefined,
): string | undefined {
  if (
    typeof value !== "string" ||
    !value.startsWith("/") ||
    value.startsWith("//")
  )
    return undefined;
  if (unsafe(value, 0x20) || value.includes("\\")) return undefined;

  try {
    const parsed = new URL(value, "http://masks.invalid");

    if (
      parsed.origin !== "http://masks.invalid" ||
      parsed.pathname.startsWith("//")
    )
      return undefined;

    return `${parsed.pathname}${parsed.search}`;
  } catch {
    return undefined;
  }
}

export function referring(request: Request): string | undefined {
  const referer = request.headers.get("referer");

  if (!referer) return undefined;

  try {
    const parsed = new URL(referer);

    return localPath(`${parsed.pathname}${parsed.search}`);
  } catch {
    return undefined;
  }
}

export function wantsJSON(request: Request): boolean {
  if (
    request.headers.get("x-requested-with")?.toLowerCase() === "xmlhttprequest"
  )
    return true;

  return !(request.headers.get("accept") ?? "").includes("text/html");
}

export async function readForm(request: Request): Promise<URLSearchParams> {
  if (Number(request.headers.get("content-length") ?? "0") > FORM_LIMIT) {
    await request.body?.cancel();
    throw tooLarge();
  }

  if (!request.body) return new URLSearchParams();

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;

  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;

    size += value.byteLength;

    if (size > FORM_LIMIT) {
      await reader.cancel();
      throw tooLarge();
    }

    chunks.push(value);
  }

  const joined = new Uint8Array(size);
  let offset = 0;

  for (const chunk of chunks) {
    joined.set(chunk, offset);
    offset += chunk.byteLength;
  }

  return new URLSearchParams(new TextDecoder().decode(joined));
}

function tooLarge(): Refused {
  return new Refused(
    "invalid_request",
    "that request body is larger than 64 KiB",
  );
}

function sameOrigin(request: Request, origin: string): boolean {
  const site = request.headers.get("sec-fetch-site");

  if (site && site !== "same-origin" && site !== "none") return false;

  const named = request.headers.get("origin");

  if (named !== null && named !== origin) return false;

  return true;
}

export function provenance(
  request: Request,
  origin: string,
): "cross-site" | "unproven" | "same-origin" {
  if (!sameOrigin(request, origin)) return "cross-site";

  const named =
    request.headers.has("sec-fetch-site") || request.headers.has("origin");

  return named ? "same-origin" : "unproven";
}

export function presented(request: Request): string | undefined {
  return request.headers
    .get("authorization")
    ?.match(/^(?:Bearer|DPoP)[ \t]+(\S+)\s*$/i)?.[1];
}

export function unsafe(value: string, highest: number): boolean {
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);

    if (code <= highest || code === 0x7f) return true;
  }

  return false;
}

export function isNetwork(error: unknown): boolean {
  return (
    error instanceof TypeError && /fetch|network|connect/i.test(error.message)
  );
}

export interface RequireAuthOptions {
  returnTo?: string;
}

export interface RequireAuth {
  (...privileges: string[]): Promise<Masked>;
  (options: RequireAuthOptions, ...privileges: string[]): Promise<Masked>;
}

export function requireArguments(asked: (string | RequireAuthOptions)[]): {
  returnTo?: string;
  privileges: string[];
} {
  const [first, ...rest] = asked;

  if (first !== undefined && typeof first === "object") {
    return {
      returnTo: localPath(first.returnTo),
      privileges: rest.filter((name) => typeof name === "string"),
    };
  }

  return {
    privileges: asked.filter((name) => typeof name === "string"),
  };
}
