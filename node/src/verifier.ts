import {
  calculateJwkThumbprint,
  EmbeddedJWK,
  type JWK,
  type JWTHeaderParameters,
  type JWTPayload,
  jwtVerify,
} from "jose";
import { DPOP, PROOF_TYPE, type ProofClaims, tokenHash } from "./dpop.js";
import { Forbidden, failure, InvalidToken, Unavailable } from "./errors.js";
import type { Issuer, Tenant } from "./issuer.js";
import { unverified } from "./jwt.js";
import { MemoryReplayStore, type ReplayStore } from "./replay.js";
import { untrailed } from "./slashes.js";

const ACCESS_TOKEN_TYPE = "at+jwt";
const PROOF_WINDOW = 60;
const LEEWAY = 30;
const REMEMBERED = PROOF_WINDOW + 2 * LEEWAY;
const TOKEN_ALGORITHMS = ["RS256", "ES256"];
const PROOF_ALGORITHMS = [
  "ES256",
  "ES384",
  "ES512",
  "PS256",
  "PS384",
  "PS512",
  "RS256",
];

export interface Claims extends JWTPayload {
  iss: string;
  sub?: string;
  aud: string | string[];
  exp: number;
  iat?: number;
  jti: string;
  client_id?: string;
  scope?: string;
  tenant?: Tenant;
  act?: Record<string, unknown>;
  cnf?: { jkt?: string };
}

export interface NodeRequest {
  method?: string;
  url?: string;
  headers: Record<string, string | string[] | undefined>;
  socket?: { encrypted?: boolean };
}

export interface VerifierOptions {
  publicURL?: string;
  replay?: ReplayStore;
  resourceMetadata?: string;
}

export class Verifier {
  readonly issuer: Issuer;
  readonly audience: string[];
  readonly publicURL?: string;
  readonly replay: ReplayStore;
  readonly resourceMetadata?: string;

  constructor(
    issuer: Issuer,
    audience: string | string[],
    options: VerifierOptions = {},
  ) {
    this.issuer = issuer;
    this.audience = Array.isArray(audience) ? audience : [audience];
    this.publicURL =
      options.publicURL === undefined
        ? undefined
        : untrailed(options.publicURL);
    this.replay = options.replay ?? new MemoryReplayStore();
    this.resourceMetadata = options.resourceMetadata;
  }

  async verify(token: string): Promise<Claims> {
    let payload: JWTPayload;

    try {
      ({ payload } = await jwtVerify(
        token,
        async (header) => this.issuer.key(header.kid),
        {
          algorithms: TOKEN_ALGORITHMS,
          typ: ACCESS_TOKEN_TYPE,
          issuer: this.issuer.url,
          audience: this.audience,
          requiredClaims: ["jti", "exp"],
          clockTolerance: LEEWAY,
        },
      ));
    } catch (error) {
      throw unverified(error, this.issuer, { token, typ: ACCESS_TOKEN_TYPE });
    }

    return payload as Claims;
  }

  async authenticate(request: Request): Promise<Claims> {
    const target = this.publicURL
      ? `${this.publicURL}${new URL(request.url).pathname}${new URL(request.url).search}`
      : request.url;

    return this.#authenticate(
      request.method,
      target,
      request.headers.get("authorization") ?? "",
      request.headers.get("dpop"),
    );
  }

  async authenticateNode(request: NodeRequest): Promise<Claims> {
    const header = (name: string) => {
      const held = request.headers[name];

      return Array.isArray(held) ? held.join(", ") : held;
    };

    const origin =
      this.publicURL ??
      `${request.socket?.encrypted ? "https" : "http"}://${header("host") ?? ""}`;

    return this.#authenticate(
      request.method ?? "GET",
      `${origin}${request.url ?? "/"}`,
      header("authorization") ?? "",
      header("dpop") ?? null,
    );
  }

  challengeHeaders(error: unknown): string[] {
    let code: string;
    let description: string;
    let scope: string | undefined;

    if (error instanceof InvalidToken) {
      code = error.missing ? "" : error.code;
      description = error.missing ? "" : error.description;
    } else if (error instanceof Forbidden) {
      code = error.code;
      description = error.description;
      scope = error.scope;
    } else {
      return [];
    }

    const parameters = [
      ...(code ? [`error="${code}"`] : []),
      ...(description ? [`error_description="${quoted(description)}"`] : []),
      ...(scope ? [`scope="${quoted(scope)}"`] : []),
      ...(this.resourceMetadata
        ? [`resource_metadata="${quoted(this.resourceMetadata)}"`]
        : []),
    ];

    return [
      ["Bearer", parameters.join(", ")].filter(Boolean).join(" "),
      `${DPOP} ${[...parameters, `algs="${PROOF_ALGORITHMS.join(" ")}"`].join(", ")}`,
    ];
  }

  refusal(error: unknown): {
    status: 401 | 403 | 503;
    headers: Record<string, string[]>;
  } {
    if (error instanceof InvalidToken) {
      return {
        status: 401,
        headers: { "www-authenticate": this.challengeHeaders(error) },
      };
    }

    if (error instanceof Forbidden) {
      return {
        status: 403,
        headers: { "www-authenticate": this.challengeHeaders(error) },
      };
    }

    return { status: 503, headers: {} };
  }

  challenge(error: unknown): Response {
    const { status, headers } = this.refusal(error);
    const held = new Headers();

    for (const [name, values] of Object.entries(headers)) {
      for (const value of values) held.append(name, value);
    }

    return new Response(
      status === 401
        ? "unauthorized"
        : status === 403
          ? "forbidden"
          : "unavailable",
      {
        status,
        headers: held,
      },
    );
  }

  async #authenticate(
    method: string,
    target: string,
    authorization: string,
    presented: string | null,
  ): Promise<Claims> {
    const space = authorization.indexOf(" ");
    const scheme = space > 0 ? authorization.slice(0, space) : "";
    const token = space > 0 ? authorization.slice(space + 1).trim() : "";

    if (!scheme || !token) {
      throw InvalidToken.of("no_token");
    }

    const claims = await this.verify(token);
    const held = typeof claims.cnf?.jkt === "string" && claims.cnf.jkt !== "";
    const bearer = scheme.toLowerCase() === "bearer";
    const dpop = scheme.toLowerCase() === DPOP.toLowerCase();

    if (bearer && !held) return claims;

    if (dpop && held) {
      await this.#proven(
        method,
        target,
        token,
        claims.cnf?.jkt as string,
        presented,
      );
      return claims;
    }

    if (bearer) {
      throw InvalidToken.of("bound_as_bearer");
    }

    throw InvalidToken.of("unbound_as_dpop");
  }

  async #proven(
    method: string,
    target: string,
    token: string,
    thumbprint: string,
    presented: string | null,
  ): Promise<void> {
    if (!presented || presented.includes(",")) {
      throw InvalidToken.of("one_proof");
    }

    let payload: JWTPayload;
    let header: JWTHeaderParameters;

    try {
      ({ payload, protectedHeader: header } = await jwtVerify(
        presented,
        EmbeddedJWK,
        { algorithms: PROOF_ALGORITHMS, typ: PROOF_TYPE },
      ));
    } catch {
      throw InvalidToken.of("proof_unsigned");
    }

    const claims = payload as unknown as ProofClaims;
    let carried: string;

    try {
      carried = await calculateJwkThumbprint(header.jwk as JWK, "sha256");
    } catch {
      throw InvalidToken.of("proof_key_unreadable");
    }

    if (!same(carried, thumbprint)) {
      throw InvalidToken.of("proof_other_key");
    }

    if (String(claims.htm ?? "").toUpperCase() !== method.toUpperCase()) {
      throw InvalidToken.of("proof_other_method");
    }

    if (!sameTarget(String(claims.htu ?? ""), target)) {
      throw InvalidToken.of("proof_other_url");
    }

    const now = Date.now() / 1000;

    if (
      typeof claims.iat !== "number" ||
      now - claims.iat > PROOF_WINDOW + LEEWAY ||
      claims.iat - now > LEEWAY
    ) {
      throw InvalidToken.of("proof_not_now");
    }

    if (!same(String(claims.ath ?? ""), await tokenHash(token))) {
      throw InvalidToken.of("proof_other_token");
    }

    if (typeof claims.jti !== "string" || claims.jti === "") {
      throw InvalidToken.of("proof_no_jti");
    }

    if (!(await this.#first(`${thumbprint}:${claims.jti}`))) {
      throw InvalidToken.of("proof_replayed");
    }
  }

  async #first(key: string): Promise<boolean> {
    let answer: unknown;

    try {
      answer = await this.replay.first(key, REMEMBERED);
    } catch (error) {
      throw new Unavailable(failure("replay_store_unreachable").description, {
        cause: error,
      });
    }

    if (typeof answer !== "boolean") {
      throw Unavailable.of("replay_store_answer");
    }

    return answer;
  }
}

export function hasScope(claims: { scope?: string }, scope: string): boolean {
  return (claims.scope ?? "").split(/\s+/).includes(scope);
}

function same(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let differs = a.length ^ b.length;

  for (let index = 0; index < Math.max(a.length, b.length); index++) {
    differs |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }

  return differs === 0 && left !== "";
}

function tidy(value: string): string {
  try {
    const held = new URL(value);
    const path = held.pathname === "/" ? "" : held.pathname;

    return `${held.origin}${path}`;
  } catch {
    return "";
  }
}

function sameTarget(left: string, right: string): boolean {
  const held = tidy(left);

  return held !== "" && held === tidy(right);
}

function quoted(value: string): string {
  let held = "";

  for (const found of value) {
    const code = found.charCodeAt(0);

    held +=
      code < 0x20 || code === 0x7f || found === '"' || found === "\\"
        ? "'"
        : found;
  }

  return held;
}
