import { FAILURES, type Failure } from "./failures.js";

export interface Described {
  code: string;
  description: string;
}

export interface RefusedOptions {
  status?: number;
  uri?: string;
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
  readonly status?: number;
  readonly uri?: string;

  constructor(
    code: string,
    description?: string,
    options: RefusedOptions = {},
  ) {
    super(worded(code, description));
    this.name = "MasksError";
    this.code = code;
    this.description = description;
    this.status = options.status;
    this.uri = options.uri;
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

  constructor(description: string, options: { code?: string } = {}) {
    super(options.code ?? "invalid_token", description);
    this.name = "InvalidToken";
  }

  static of(key: Failure, ...values: unknown[]): InvalidToken {
    const { code, description } = failure(key, ...values);

    return new InvalidToken(description, { code });
  }
}

export class Insecure extends MasksError {
  declare readonly description: string;

  constructor(description: string) {
    super("insecure_url", description);
    this.name = "Insecure";
  }

  static of(key: Failure, ...values: unknown[]): Insecure {
    return new Insecure(saying(key, ...values));
  }
}

const KINDS = new Set(["MasksError", "Refused", "InvalidToken", "Insecure"]);

export function isMasksError(error: unknown): error is MasksError {
  return (
    error instanceof MasksError ||
    (error instanceof Error &&
      KINDS.has(error.name) &&
      typeof (error as { code?: unknown }).code === "string")
  );
}

export function hasCode(error: unknown, code: string): boolean {
  return isMasksError(error) && error.code === code;
}
