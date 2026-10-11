import { decoded } from "./errors.js";

export interface Options {
  fetch?: typeof fetch;
  allowPlainHTTP?: boolean;
}

export async function getJSON<T>(
  options: Options,
  target: string,
  bearer?: string,
): Promise<T> {
  return sendJSON<T>(options, "GET", target, bearer);
}

export async function sendJSON<T>(
  options: Options,
  method: string,
  target: string,
  bearer?: string,
  body?: unknown,
  signal?: AbortSignal,
): Promise<T> {
  const headers: Record<string, string> = { accept: "application/json" };

  if (body !== undefined) headers["content-type"] = "application/json";
  if (bearer) headers.authorization = `Bearer ${bearer}`;

  const response = await (options.fetch ?? globalThis.fetch)(target, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    redirect: "manual",
    signal,
  });

  if (response.status === 204) {
    await response.body?.cancel();
    return undefined as T;
  }

  return decoded<T>(response);
}
