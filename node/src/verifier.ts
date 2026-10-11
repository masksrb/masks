import {
  calculateJwkThumbprint,
  EmbeddedJWK,
  type JWK,
  type JWTHeaderParameters,
  type JWTPayload,
  jwtVerify,
} from "jose";
import { DPOP, PROOF_TYPE, type ProofClaims, tokenHash } from "./dpop.js";
import { InvalidTokenError } from "./errors.js";
import type { Issuer, Tenant } from "./issuer.js";

const ACCESS_TOKEN_TYPE = "at+jwt";
const PROOF_WINDOW = 60;
const LEEWAY = 30;
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
}

export class Verifier {
  readonly issuer: Issuer;
  readonly audience: string[];
  readonly publicURL?: string;
  readonly #replays = new Map<string, number>();
  #swept = 0;

  constructor(
    issuer: Issuer,
    audience: string | string[],
    options: VerifierOptions = {},
  ) {
    this.issuer = issuer;
    this.audience = Array.isArray(audience) ? audience : [audience];
    this.publicURL = options.publicURL?.replace(/\/+$/, "");
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
      if (error instanceof InvalidTokenError) throw error;

      throw new InvalidTokenError(
        error instanceof Error ? error.message : "that token is not valid",
      );
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
    const description = (
      error instanceof Error ? error.message : "that token is not valid"
    )
      .replace(/^masks: invalid token: /, "")
      .replace(/["\\]/g, "'");
    const challenge = `error="invalid_token", error_description="${description}"`;

    return [
      `Bearer ${challenge}`,
      `${DPOP} ${challenge}, algs="${PROOF_ALGORITHMS.join(" ")}"`,
    ];
  }

  challenge(error: unknown): Response {
    const headers = new Headers();

    for (const value of this.challengeHeaders(error)) {
      headers.append("www-authenticate", value);
    }

    return new Response("unauthorized", { status: 401, headers });
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
      throw new InvalidTokenError("the request carries no token");
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
      throw new InvalidTokenError(
        "that token is held to a key and is presented with DPoP",
      );
    }

    throw new InvalidTokenError("that token is presented as a Bearer token");
  }

  async #proven(
    method: string,
    target: string,
    token: string,
    thumbprint: string,
    presented: string | null,
  ): Promise<void> {
    if (!presented || presented.includes(",")) {
      throw new InvalidTokenError("exactly one DPoP proof is required");
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
      throw new InvalidTokenError(
        "that proof was not signed by the public key it carries",
      );
    }

    const claims = payload as unknown as ProofClaims;
    const carried = await calculateJwkThumbprint(header.jwk as JWK, "sha256");

    if (!same(carried, thumbprint)) {
      throw new InvalidTokenError(
        "that proof was signed by another key than the token is held to",
      );
    }

    if (String(claims.htm ?? "").toUpperCase() !== method.toUpperCase()) {
      throw new InvalidTokenError("that proof was made for another method");
    }

    if (!sameTarget(String(claims.htu ?? ""), target)) {
      throw new InvalidTokenError("that proof was made for another URL");
    }

    const now = Date.now() / 1000;

    if (
      typeof claims.iat !== "number" ||
      now - claims.iat > PROOF_WINDOW + LEEWAY ||
      claims.iat - now > LEEWAY
    ) {
      throw new InvalidTokenError("that proof was not made just now");
    }

    if (!same(String(claims.ath ?? ""), await tokenHash(token))) {
      throw new InvalidTokenError("that proof was made for another token");
    }

    if (!claims.jti || !this.#first(`${thumbprint}:${claims.jti}`)) {
      throw new InvalidTokenError("that proof has already been used");
    }
  }

  #first(id: string): boolean {
    const now = Date.now();

    if (now - this.#swept > PROOF_WINDOW * 1000) {
      this.#swept = now;

      for (const [key, at] of this.#replays) {
        if (now - at > (PROOF_WINDOW + 2 * LEEWAY) * 1000) {
          this.#replays.delete(key);
        }
      }
    }

    if (this.#replays.has(id)) return false;

    this.#replays.set(id, now);

    return true;
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
