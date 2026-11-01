import { FAILURES, type Failure } from "./failures.js";

export interface Described {
  code: string;
  description: string;
}

export interface RefusedOptions {
  uri?: string;
  status?: number;
  cause?: unknown;
}

export function failure(key: Failure, ...values: unknown[]): Described {
  const [code, template] = FAILURES[key];
  let index = 0;

  return {
    code,
    description: template.replaceAll(/\{[a-z_]+\}/g, () =>
      String(values[index++]),
    ),
  };
}

export function saying(key: Failure, ...values: unknown[]): string {
  return failure(key, ...values).description;
}

function worded(code: string, description?: string): string {
  return description ? `masks: ${code}: ${description}` : `masks: ${code}`;
}

export class MasksError extends Error {
  readonly code: string;
  readonly description?: string;
  readonly uri?: string;
  readonly status?: number;

  constructor(
    code: string,
    description?: string,
    options: RefusedOptions = {},
  ) {
    super(worded(code, description), { cause: options.cause });
    this.name = "MasksError";
    this.code = code;
    this.description = description;
    this.uri = options.uri;
    this.status = options.status;
  }
}

export class Refused extends MasksError {
  constructor(
    code: string,
    description?: string,
    options: RefusedOptions = {},
  ) {
    super(code, description, options);
    this.name = "Refused";
  }

  static of(key: Failure, ...values: unknown[]): Refused {
    const { code, description } = failure(key, ...values);

    return new Refused(code, description);
  }
}

export class InvalidToken extends MasksError {
  declare readonly description: string;
  readonly missing: boolean;

  constructor(
    description: string,
    options: { code?: string; missing?: boolean; cause?: unknown } = {},
  ) {
    super(options.code ?? "invalid_token", description, {
      cause: options.cause,
    });
    this.name = "InvalidToken";
    this.missing = options.missing ?? false;
  }

  static of(key: Failure, ...values: unknown[]): InvalidToken {
    const { code, description } = failure(key, ...values);

    return new InvalidToken(description, { code, missing: key === "no_token" });
  }
}

export class Forbidden extends MasksError {
  declare readonly description: string;
  readonly scope?: string;

  constructor(
    code: string,
    description: string,
    options: { scope?: string } = {},
  ) {
    super(code, description);
    this.name = "Forbidden";
    this.scope = options.scope;
  }

  static of(key: Failure, ...values: unknown[]): Forbidden {
    const { code, description } = failure(key, ...values);

    return new Forbidden(code, description);
  }
}

export class Unavailable extends MasksError {
  declare readonly description: string;

  constructor(description: string, options: { cause?: unknown } = {}) {
    super("temporarily_unavailable", description, { cause: options.cause });
    this.name = "Unavailable";
  }

  static of(key: Failure, ...values: unknown[]): Unavailable {
    return new Unavailable(failure(key, ...values).description);
  }
}

export class Insecure extends MasksError {
  declare readonly description: string;

  constructor(description: string) {
    super("insecure_url", description);
    this.name = "Insecure";
  }

  static of(key: Failure, ...values: unknown[]): Insecure {
    return new Insecure(failure(key, ...values).description);
  }
}

export class Foreign extends MasksError {
  declare readonly description: string;

  constructor(description: string) {
    super("foreign_origin", description);
    this.name = "Foreign";
  }

  static of(key: Failure, ...values: unknown[]): Foreign {
    return new Foreign(failure(key, ...values).description);
  }
}

export class DelegationRefused extends MasksError {
  readonly secret?: string;

  constructor(
    code: string,
    description?: string,
    options: { secret?: string; status?: number; cause?: unknown } = {},
  ) {
    super(code, description, { status: options.status, cause: options.cause });
    this.name = "DelegationRefused";
    this.secret = options.secret;
  }

  get signedInAgain(): boolean {
    return (
      this.code === "login_required" || this.code === "interaction_required"
    );
  }

  static of(key: Failure, ...values: unknown[]): DelegationRefused {
    const { code, description } = failure(key, ...values);

    return new DelegationRefused(code, description);
  }
}

export class DelegationUnavailable extends MasksError {
  declare readonly description: string;
  readonly secret?: string;

  constructor(
    description: string,
    options: { secret?: string; cause?: unknown } = {},
  ) {
    super("temporarily_unavailable", description, { cause: options.cause });
    this.name = "DelegationUnavailable";
    this.secret = options.secret;
  }

  static of(key: Failure, ...values: unknown[]): DelegationUnavailable {
    return new DelegationUnavailable(failure(key, ...values).description);
  }
}

const KINDS = new Set([
  "MasksError",
  "Refused",
  "InvalidToken",
  "Forbidden",
  "Unavailable",
  "Insecure",
  "Foreign",
  "DelegationRefused",
  "DelegationUnavailable",
]);

function coded(error: unknown): error is Error & { code: string } {
  return (
    error instanceof Error &&
    typeof (error as { code?: unknown }).code === "string"
  );
}

export function isMasksError(error: unknown): error is MasksError {
  return error instanceof MasksError || (coded(error) && KINDS.has(error.name));
}

export function isRefused(error: unknown): error is Refused {
  return error instanceof Refused || (coded(error) && error.name === "Refused");
}

export function hasCode(error: unknown, code: string): boolean {
  return isMasksError(error) && error.code === code;
}

export function rejected(error: unknown): boolean {
  return isRefused(error) && (error.status ?? 0) < 500 && error.status !== 429;
}

export const READ_LIMIT = 1 << 20;

export async function bounded(response: Response): Promise<string> {
  const declared = Number(response.headers.get("content-length") ?? "0");

  if (declared > READ_LIMIT) {
    await response.body?.cancel();
    throw Refused.of("too_large", redacted(response.url));
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
      throw Refused.of("too_large", redacted(response.url));
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

export async function refused(response: Response): Promise<Refused> {
  let body: Record<string, unknown> = {};

  try {
    body = JSON.parse(await bounded(response));
  } catch {
    body = {};
  }

  if (typeof body.error !== "string" || body.error === "") {
    const { code, description } = failure(
      "answered_status",
      redacted(response.url),
      response.status,
    );

    return new Refused(code, description, { status: response.status });
  }

  return new Refused(
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
    throw Refused.of("not_json", redacted(response.url));
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
