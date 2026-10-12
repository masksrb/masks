export class MasksError extends Error {
  readonly code: string;
  readonly description?: string;
  readonly uri?: string;
  readonly status?: number;

  constructor(
    code: string,
    description?: string,
    options: { uri?: string; status?: number } = {},
  ) {
    super(description ? `masks: ${code}: ${description}` : `masks: ${code}`);
    this.name = "MasksError";
    this.code = code;
    this.description = description;
    this.uri = options.uri;
    this.status = options.status;
  }
}

export class InvalidTokenError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(`masks: invalid token: ${message}`, options);
    this.name = "InvalidTokenError";
  }
}

export class InsecureError extends Error {
  constructor(target: string) {
    super(`masks: plain http is allowed only on this machine: ${target}`);
    this.name = "InsecureError";
  }
}

export class ForeignError extends Error {
  constructor(message: string) {
    super(`masks: that URL belongs to another origin: ${message}`);
    this.name = "ForeignError";
  }
}

export function hasCode(error: unknown, code: string): boolean {
  return error instanceof MasksError && error.code === code;
}

export const READ_LIMIT = 1 << 20;

export async function bounded(response: Response): Promise<string> {
  const declared = Number(response.headers.get("content-length") ?? "0");

  if (declared > READ_LIMIT) {
    await response.body?.cancel();
    throw new MasksError(
      "server_error",
      `${redacted(response.url)} answered with more than a megabyte`,
    );
  }

  if (!response.body) return "";

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;

  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;

    size += value.byteLength;

    if (size > READ_LIMIT) {
      await reader.cancel();
      throw new MasksError(
        "server_error",
        `${redacted(response.url)} answered with more than a megabyte`,
      );
    }

    chunks.push(value);
  }

  const joined = new Uint8Array(size);
  let offset = 0;

  for (const chunk of chunks) {
    joined.set(chunk, offset);
    offset += chunk.byteLength;
  }

  return new TextDecoder().decode(joined);
}

export async function refused(response: Response): Promise<MasksError> {
  let body: Record<string, unknown> = {};

  try {
    body = JSON.parse(await bounded(response));
  } catch {
    body = {};
  }

  if (typeof body.error !== "string" || body.error === "") {
    return new MasksError(
      "server_error",
      `${redacted(response.url)} answered ${response.status}`,
      { status: response.status },
    );
  }

  return new MasksError(
    body.error,
    typeof body.error_description === "string"
      ? body.error_description
      : undefined,
    {
      uri: typeof body.error_uri === "string" ? body.error_uri : undefined,
      status: response.status,
    },
  );
}

export async function decoded<T>(response: Response): Promise<T> {
  if (response.status >= 300) throw await refused(response);

  const text = await bounded(response);

  if (text.trim() === "") return undefined as T;

  try {
    return JSON.parse(text) as T;
  } catch {
    throw new MasksError(
      "server_error",
      `${redacted(response.url)} answered with something other than JSON`,
    );
  }
}

export function redacted(target: string): string {
  try {
    const held = new URL(target);
    held.username = "";
    held.password = "";
    held.search = "";

    return held.toString();
  } catch {
    return "that address";
  }
}
