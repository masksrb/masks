import { scopes as scopesOf } from "../client.js";
import { Forbidden, failure, InvalidToken } from "../errors.js";
import type { Claims, Verifier } from "../verifier.js";
import type { Core } from "./core.js";
import { Masked } from "./masked.js";
import { unique } from "./privileges.js";
import { localPath, presented, referring, wantsJSON } from "./requests.js";
import { errorResponse, headersWith, json, redirect } from "./responses.js";
import { type FlowData, now, type Visit } from "./session.js";

export type RefusalKind =
  | "handshake"
  | "login"
  | "step_up"
  | "forbidden"
  | "invalid_token"
  | "unavailable";

export class Refusal {
  readonly kind: RefusalKind;
  readonly url?: string;
  readonly error?: Forbidden | InvalidToken;
  readonly cookies: string[];
  readonly #request: Request;
  readonly #answer: (request: Request) => Response;

  constructor(fields: {
    kind: RefusalKind;
    request: Request;
    cookies: string[];
    answer: (request: Request) => Response;
    url?: string;
    error?: Forbidden | InvalidToken;
  }) {
    this.kind = fields.kind;
    this.url = fields.url;
    this.error = fields.error;
    this.cookies = fields.cookies;
    this.#request = fields.request;
    this.#answer = fields.answer;
  }

  toResponse(request: Request = this.#request): Response {
    return this.#answer(request);
  }
}

export type Outcome =
  | { masked: Masked; cookies: string[]; refusal?: undefined }
  | { masked?: undefined; cookies?: undefined; refusal: Refusal };

export interface CheckOptions {
  privileges?: string[];
  refresh?: boolean;
  returnTo?: string;
}

const STEP_UP_WITHIN = 300;

export async function check(
  core: Core,
  request: Request,
  asked: CheckOptions = {},
): Promise<Outcome> {
  const wanted = (asked.privileges ?? [])
    .flat()
    .map((name) => core.privileges.get(name));
  const visit = await core.visit(request);

  if (!(await core.configured(visit))) {
    return { refusal: handshakeRefusal(core, visit, asked.returnTo) };
  }

  const data =
    asked.refresh === false
      ? (await core.sessions.read(visit))?.data
      : await core.current(visit);
  const masked = core.masked(visit, data);

  if (!masked.signedIn) {
    const refreshable =
      asked.refresh === false && !!data?.tokens?.refresh_token;

    return {
      refusal: loginRefusal(core, visit, asked.returnTo, refreshable),
    };
  }

  try {
    for (const privilege of wanted) masked.member(privilege);
  } catch (error) {
    if (error instanceof Forbidden) return { refusal: forbidden(visit, error) };
    throw error;
  }

  const missing = wanted
    .filter(
      (privilege) => !privilege.scopes.every((scope) => masked.permits(scope)),
    )
    .map((privilege) => privilege.name);

  if (missing.length === 0) return { masked, cookies: visit.handOut() };

  if (steppedUp(await core.sessions.readFlow(visit), missing)) {
    const { code, description } = failure(
      "no_privilege",
      missing.join(" and "),
    );
    const error = new Forbidden(code, description, {
      scope: unique(
        missing.flatMap((name) => core.privileges.get(name).scopes),
      ).join(" "),
    });

    return { refusal: forbidden(visit, error) };
  }

  const url = core.loginURL({
    returnTo: returnPath(visit, asked.returnTo),
    privilege: missing,
  });

  return {
    refusal: new Refusal({
      kind: "step_up",
      request,
      url,
      cookies: visit.out,
      answer: (asking) =>
        wantsJSON(asking)
          ? json(
              403,
              {
                error: "privilege_required",
                privileges: missing,
                login_url: url,
              },
              visit.out,
            )
          : redirect(url, visit.out),
    }),
  };
}

export function steppedUp(flow: FlowData, names: string[]): boolean {
  const stepped = flow.steppedUp;

  return (
    !!stepped &&
    names.every((name) => stepped.privileges.includes(name)) &&
    stepped.at > now() - STEP_UP_WITHIN
  );
}

export async function protect(
  core: Core,
  request: Request,
  names: string[],
): Promise<Outcome> {
  const wanted = names.flat().map((name) => core.privileges.get(name));
  const visit = await core.visit(request);
  let verifier: Verifier | undefined;
  let claims: Claims;

  try {
    verifier = await core.verifier(visit);
    claims = await verifier.authenticate(request);
  } catch (error) {
    if (verifier && error instanceof InvalidToken) {
      return { refusal: challenged(request, verifier, error) };
    }

    return {
      refusal: new Refusal({
        kind: "unavailable",
        request,
        cookies: [],
        answer: () =>
          json(
            503,
            {
              error: "temporarily_unavailable",
              error_description: "the token could not be checked",
            },
            [],
          ),
      }),
    };
  }

  const masked = new Masked({
    claims,
    scopes: scopesOf(claims),
    signedIn: true,
    privileges: core.privileges,
    accessToken: presented(request),
    tokenType: claims.cnf?.jkt ? "DPoP" : "Bearer",
    expiresAt: claims.exp,
    accountURL: `${visit.issuerURL}/`,
  });

  try {
    for (const privilege of wanted) {
      for (const scope of privilege.scopes) {
        if (!masked.permits(scope)) {
          const { code, description } = failure("no_scope", scope);

          throw new Forbidden(code, description, {
            scope: privilege.scopes.join(" "),
          });
        }
      }

      masked.member(privilege);
    }
  } catch (error) {
    if (!(error instanceof Forbidden)) throw error;

    return { refusal: challenged(request, verifier, error) };
  }

  return { masked, cookies: [] };
}

export async function guard(
  core: Core,
  request: Request,
  names: string[],
): Promise<Outcome> {
  if (request.headers.get("authorization"))
    return protect(core, request, names);

  const visit = await core.visit(request);
  const session = await core.sessions.read(visit);

  if (!session?.data.tokens && wantsJSON(request)) {
    return protect(core, request, names);
  }

  return check(core, request, { privileges: names });
}

export function handshakeRefusal(
  core: Core,
  visit: Visit,
  asked?: string,
): Refusal {
  const url = core.handshakeURL(returnPath(visit, asked));

  return new Refusal({
    kind: "handshake",
    request: visit.request,
    url,
    cookies: visit.out,
    answer: (asking) =>
      wantsJSON(asking) ? handshakeJSON(core, visit) : redirect(url, visit.out),
  });
}

export function handshakeJSON(core: Core, visit: Visit): Response {
  return json(
    401,
    {
      signed_in: false,
      error: "handshake_required",
      handshake_url: core.handshakePath,
    },
    visit.out,
  );
}

export function loginRefusal(
  core: Core,
  visit: Visit,
  asked?: string,
  refreshable = false,
): Refusal {
  const returnTo = returnPath(visit, asked);
  const query = returnTo
    ? `?${new URLSearchParams({ return_to: returnTo })}`
    : "";
  const url = refreshable
    ? `${core.basePath}/refresh${query}`
    : core.loginURL({ returnTo });

  return new Refusal({
    kind: "login",
    request: visit.request,
    url,
    cookies: visit.out,
    answer: (asking) =>
      wantsJSON(asking)
        ? loginJSON(core, visit, asking)
        : redirect(url, visit.out),
  });
}

export function loginJSON(
  core: Core,
  visit: Visit,
  asking: Request = visit.request,
): Response {
  return json(
    401,
    {
      signed_in: false,
      error: "login_required",
      login_url: core.loginURL({ returnTo: referring(asking) }),
    },
    visit.out,
  );
}

export function answer(
  visit: Visit,
  status: number,
  code: string,
  description: string,
  asJSON = false,
): Response {
  return errorResponse(
    visit.request,
    status,
    code,
    description,
    visit.out,
    asJSON,
  );
}

export function describe(error: Error): string {
  return error.message.replace(/^masks: (?:[a-z_]+: )?/, "");
}

function forbidden(visit: Visit, error: Forbidden): Refusal {
  return new Refusal({
    kind: "forbidden",
    request: visit.request,
    error,
    cookies: visit.out,
    answer: (asking) =>
      errorResponse(asking, 403, error.code, error.description, visit.out),
  });
}

function challenged(
  request: Request,
  verifier: Verifier,
  error: InvalidToken | Forbidden,
): Refusal {
  const { status, headers } = verifier.refusal(error);
  const body = { error: error.code, error_description: error.description };

  return new Refusal({
    kind: error instanceof InvalidToken ? "invalid_token" : "forbidden",
    request,
    error,
    cookies: [],
    answer: () => {
      const held = headersWith([], {
        "content-type": "application/json",
        "cache-control": "no-store",
      });

      for (const [name, values] of Object.entries(headers)) {
        for (const value of values) held.append(name, value);
      }

      return new Response(JSON.stringify(body), { status, headers: held });
    },
  });
}

function returnPath(
  visit: Visit,
  asked: string | undefined,
): string | undefined {
  return (
    localPath(asked) ??
    (visit.request.method === "GET"
      ? `${visit.url.pathname}${visit.url.search}`
      : referring(visit.request))
  );
}
