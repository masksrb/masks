import { ForbiddenError } from "../claims.js";
import { scopes as scopesOf } from "../client.js";
import { InvalidTokenError } from "../errors.js";
import type { Claims, Verifier } from "../verifier.js";
import type { Core } from "./core.js";
import { Masked } from "./masked.js";
import { unique } from "./privileges.js";
import {
  localPath,
  presented,
  referring,
  unsafe,
  wantsJSON,
} from "./requests.js";
import { errorResponse, json, redirect } from "./responses.js";
import { now, type Visit } from "./session.js";

export type Outcome =
  | {
      masked: Masked;
      cookies: string[];
      response?: undefined;
      error?: undefined;
    }
  | {
      masked?: undefined;
      cookies?: undefined;
      response: Response;
      error?: ForbiddenError;
    };

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
    return { response: refuse(core, visit, "handshake_required") };
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
      response: refuse(
        core,
        visit,
        "login_required",
        asked.returnTo,
        refreshable,
      ),
    };
  }

  try {
    for (const privilege of wanted) masked.member(privilege);
  } catch (error) {
    if (error instanceof ForbiddenError)
      return { response: forbid(visit, error), error };
    throw error;
  }

  const missing = wanted
    .filter(
      (privilege) => !privilege.scopes.every((scope) => masked.permits(scope)),
    )
    .map((privilege) => privilege.name);

  if (missing.length === 0) return { masked, cookies: visit.handOut() };

  const flow = await core.sessions.readFlow(visit);
  const stepped = flow.steppedUp;

  if (
    stepped &&
    missing.every((name) => stepped.privileges.includes(name)) &&
    stepped.at > now() - STEP_UP_WITHIN
  ) {
    const error = new ForbiddenError(
      "insufficient_scope",
      `this account does not hold the ${missing.join(" and ")} privilege`,
      {
        scope: unique(
          missing.flatMap((name) => core.privileges.get(name).scopes),
        ).join(" "),
      },
    );

    return { response: forbid(visit, error), error };
  }

  const returnTo =
    asked.returnTo ??
    (request.method === "GET"
      ? `${visit.url.pathname}${visit.url.search}`
      : referring(request));
  const url = core.loginURL({ returnTo, privilege: missing });

  if (wantsJSON(request)) {
    return {
      response: json(
        403,
        { error: "privilege_required", privileges: missing, login_url: url },
        visit.out,
      ),
    };
  }

  return { response: redirect(url, visit.out) };
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
    if (verifier && error instanceof InvalidTokenError) {
      const headers = new Headers({ "cache-control": "no-store" });
      for (const value of verifier.challengeHeaders(error))
        headers.append("www-authenticate", value);

      return {
        response: Response.json(
          { error: "invalid_token", error_description: describe(error) },
          { status: 401, headers },
        ),
      };
    }

    return {
      response: json(
        503,
        {
          error: "temporarily_unavailable",
          error_description: "the token could not be checked",
        },
        [],
      ),
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
          throw new ForbiddenError(
            "insufficient_scope",
            `this token does not carry ${scope}`,
            {
              scope: privilege.scopes.join(" "),
            },
          );
        }
      }

      masked.member(privilege);
    }
  } catch (error) {
    if (!(error instanceof ForbiddenError)) throw error;

    const headers = new Headers({ "cache-control": "no-store" });
    const scope = error.scope ? `, scope="${quote(error.scope)}"` : "";

    headers.set(
      "www-authenticate",
      `Bearer error="${error.code}", error_description="${quote(error.description)}"${scope}, resource_metadata="${core.metadataURL(visit)}"`,
    );

    return {
      response: Response.json(
        { error: error.code, error_description: error.description },
        { status: 403, headers },
      ),
    };
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

export function refuse(
  core: Core,
  visit: Visit,
  reason: "handshake_required" | "login_required",
  asked?: string,
  refreshable = false,
): Response {
  if (wantsJSON(visit.request)) return refuseJSON(core, visit, reason);

  const returnTo =
    localPath(asked) ??
    (visit.request.method === "GET"
      ? `${visit.url.pathname}${visit.url.search}`
      : referring(visit.request));

  if (reason === "handshake_required")
    return redirect(core.handshakeURL(returnTo), visit.out);

  if (refreshable) {
    const query = returnTo
      ? `?${new URLSearchParams({ return_to: returnTo })}`
      : "";

    return redirect(`${core.basePath}/refresh${query}`, visit.out);
  }

  return redirect(core.loginURL({ returnTo }), visit.out);
}

export function refuseJSON(
  core: Core,
  visit: Visit,
  reason: "handshake_required" | "login_required",
): Response {
  if (reason === "handshake_required") {
    return json(
      401,
      { signed_in: false, error: reason, handshake_url: core.handshakePath },
      visit.out,
    );
  }

  return json(
    401,
    {
      signed_in: false,
      error: reason,
      login_url: core.loginURL({ returnTo: referring(visit.request) }),
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

function forbid(visit: Visit, error: ForbiddenError): Response {
  return answer(visit, 403, error.code, error.description);
}

export function describe(error: Error): string {
  return error.message.replace(/^masks: (invalid token: )?/, "");
}

function quote(value: string): string {
  return [...value]
    .map((found) =>
      unsafe(found, 0x1f) || found === '"' || found === "\\" ? " " : found,
    )
    .join("")
    .trim();
}
