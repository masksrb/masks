import { organizationKey } from "../claims.js";
import type { Token } from "../client.js";
import { InvalidTokenError, MasksError, UnavailableError } from "../errors.js";
import type { IdTokenClaims, LogoutToken } from "../idtoken.js";
import { random } from "../key.js";
import { avatarResponse } from "./avatar.js";
import type { Core } from "./core.js";
import {
  answer,
  describe,
  handshakeJSON,
  loginJSON,
  steppedUp,
} from "./guard.js";
import type { HandshakeHost } from "./handshakes.js";
import { acceptLogout } from "./logouts.js";
import { unique } from "./privileges.js";
import {
  isNetwork,
  localPath,
  readForm,
  resolve,
  sameOrigin,
  wantsJSON,
} from "./requests.js";
import { json, redirect, text } from "./responses.js";
import {
  claim,
  FLOW_LIFETIME,
  type FlowData,
  held,
  keep,
  now,
  type Visit,
} from "./session.js";

const RESTART_WITHIN = 60;

export async function handle(
  core: Core,
  request: Request,
  metadata: () => Promise<Record<string, unknown>>,
): Promise<Response | undefined> {
  if (!core.owns(new URL(request.url).pathname)) return undefined;

  const visit = await core.visit(request);
  const path = visit.url.pathname;
  const base = core.basePath;

  if (request.method === "GET" && path === core.metadataPath(visit)) {
    return json(200, await metadata(), [], {
      "cache-control": "public, max-age=300",
    });
  }

  if (path !== base && !path.startsWith(`${base}/`)) return undefined;

  const route = path.slice(base.length).replace(/\/+$/, "") || "/";
  const method = request.method.toUpperCase();

  try {
    switch (`${method} ${route}`) {
      case "GET /":
        return await start(core, visit);
      case "GET /callback":
        return await callback(core, visit);
      case "GET /refresh":
        return await refreshRoute(core, visit);
      case "GET /session":
        return await sessionRoute(core, visit);
      case "GET /avatar":
        return await avatar(core, visit);
      case "GET /logout":
      case "POST /logout":
      case "DELETE /logout":
        return await logout(core, visit);
      case "GET /logout/return":
        return await logoutReturn(core, visit);
      case "POST /logout/backchannel":
        return await backchannel(core, visit);
      case "GET /handshake":
        return await core.handshakes.show(request);
      case "POST /handshake":
        return await core.handshakes.create(request);
      case "DELETE /handshake":
      case "POST /handshake/disconnect":
        return await core.handshakes.destroy(request);
      case "GET /handshake/callback":
        return await core.handshakes.callback(request);
      default:
        return text(404, "not found", visit.out);
    }
  } catch (error) {
    if (error instanceof MasksError) {
      return answer(visit, 400, error.code, error.description ?? error.code);
    }

    if (error instanceof UnavailableError || isNetwork(error)) {
      return answer(
        visit,
        503,
        "temporarily_unavailable",
        "masks could not be reached",
      );
    }

    throw error;
  }
}

async function start(core: Core, visit: Visit): Promise<Response> {
  await core.handshakes.stillRegistered(visit.request);

  const client = await core.client(visit);

  const params = visit.url.searchParams;
  const returnTo = core.returnTo(params.get("return_to"));

  if (!client) return redirect(core.handshakeURL(returnTo), visit.out);

  const named = core.privileges.known(
    (params.get("privilege") ?? "").split(/\s+/).filter(Boolean),
  );
  const scope = named.length
    ? unique([
        ...core.scope,
        ...named.flatMap((name) => core.privileges.get(name).scopes),
      ])
    : core.scope;
  const organization =
    organizationKey(params.get("organization")) ??
    organizationKey(await resolve(core.options.organization, visit.request));
  const redirectURI = core.redirectURI(visit);
  const resource = [visit.resource];
  const started = await client.start({
    redirectURI,
    scope,
    resource,
    organization,
  });
  const flow = await core.sessions.readFlow(visit);

  flow.requests = keep(flow.requests, started.state, {
    verifier: started.verifier,
    nonce: started.nonce,
    returnTo,
    redirectURI,
    resource,
    until: now() + FLOW_LIFETIME,
  });

  if (named.length > 0) flow.steppedUp = { privileges: named, at: now() };

  await core.sessions.writeFlow(visit, flow);

  return redirect(started.url, visit.out);
}

async function callback(core: Core, visit: Visit): Promise<Response> {
  const params = visit.url.searchParams;
  const flow = await core.sessions.readFlow(visit);
  const state = params.get("state") ?? "";
  const pending = claim(flow.requests, state);

  if (pending) await core.sessions.writeFlow(visit, flow);

  if (params.get("error") && !pending) {
    return answer(
      visit,
      400,
      "invalid_state",
      "masks refused a sign-in that this browser did not start, or one that expired",
    );
  }

  if (params.get("error")) {
    return answer(
      visit,
      400,
      params.get("error") ?? "access_denied",
      params.get("error_description") ?? "masks did not sign you in",
    );
  }

  if (!pending) return stale(core, visit, flow);

  const client = await core.client(visit);

  if (!client) return redirect(core.handshakePath, visit.out);

  let signedIn: { token: Token; claims?: IdTokenClaims };

  try {
    signedIn = await client.complete(params, { ...pending, state });
  } catch (error) {
    if (
      error instanceof MasksError &&
      error.code === "invalid_client" &&
      (await core.handshakes.forget(visit.request))
    ) {
      return redirect(core.handshakePath, visit.out);
    }

    throw error;
  }

  const identity = await core.identity(client, signedIn.token, signedIn.claims);
  const signedInAt = now();

  await core.sessions.write(
    visit,
    {
      issuer: visit.issuerURL,
      tokens: held(signedIn.token),
      identity,
      signedInAt,
      expiresAt: signedInAt + core.maxAge,
    },
    true,
  );

  return redirect(
    pending.returnTo ?? core.options.afterSignIn ?? "/",
    visit.out,
  );
}

async function stale(
  core: Core,
  visit: Visit,
  flow: FlowData,
): Promise<Response> {
  const masked = core.masked(visit, await core.current(visit));

  if (masked.signedIn)
    return redirect(core.options.afterSignIn ?? "/", visit.out);

  if (
    !wantsJSON(visit.request) &&
    (flow.restartedAt ?? 0) < now() - RESTART_WITHIN
  ) {
    flow.restartedAt = now();
    await core.sessions.writeFlow(visit, flow);

    return redirect(core.basePath, visit.out);
  }

  return answer(
    visit,
    400,
    "invalid_state",
    "that sign-in request is not one this browser started, or it expired",
  );
}

async function refreshRoute(core: Core, visit: Visit): Promise<Response> {
  const returnTo = core.returnTo(visit.url.searchParams.get("return_to"));
  const masked = core.masked(visit, await core.current(visit));

  if (masked.signedIn)
    return redirect(returnTo ?? core.options.afterSignIn ?? "/", visit.out);

  return redirect(core.loginURL({ returnTo }), visit.out);
}

async function sessionRoute(core: Core, visit: Visit): Promise<Response> {
  if (!(await core.configured(visit))) return handshakeJSON(core, visit);

  const masked = core.masked(visit, await core.current(visit));

  if (!masked.signedIn) return loginJSON(core, visit);

  return json(200, masked.toJSON(), visit.out);
}

async function avatar(core: Core, visit: Visit): Promise<Response> {
  const data = await core.current(visit);
  const masked = core.masked(visit, data);
  const photo = masked.avatars.photo;

  if (!masked.signedIn || !photo || !data?.tokens)
    return text(404, "not found", visit.out);

  return avatarResponse(
    {
      photo,
      issuer: visit.issuerURL,
      token: data.tokens,
      size: visit.url.searchParams.get("size"),
      fetch: core.options.fetch,
      bytes: core.options.avatarBytes,
    },
    visit.out,
  );
}

async function logout(core: Core, visit: Visit): Promise<Response> {
  if (!sameOrigin(visit.request, visit.origin)) {
    return answer(
      visit,
      403,
      "forbidden",
      "signing out is only asked for from this app",
    );
  }

  const session = await core.sessions.read(visit);
  const client = await core.client(visit);
  const refresh = session?.data.tokens?.refresh_token;

  if (client && refresh) {
    try {
      await client.revoke(refresh, "refresh_token");
    } catch {}
  }

  await core.sessions.forget(visit);

  const everywhere =
    core.options.signOutOfIssuer === true ||
    visit.url.searchParams.has("everywhere");
  let upstream: string | undefined;

  if (everywhere && client) {
    try {
      const state = random(16);
      const flow = await core.sessions.readFlow(visit);

      flow.logouts = keep(flow.logouts, state, {
        until: now() + FLOW_LIFETIME,
      });
      await core.sessions.writeFlow(visit, flow);

      upstream = client.endSessionURL({
        postLogoutRedirectURI: core.logoutReturn(visit),
        state,
      });
    } catch {
      upstream = undefined;
    }
  }

  if (wantsJSON(visit.request)) {
    return json(
      200,
      { signed_in: false, ...(upstream ? { logout_url: upstream } : {}) },
      visit.out,
    );
  }

  return redirect(upstream ?? core.options.afterSignOut ?? "/", visit.out, 303);
}

async function logoutReturn(core: Core, visit: Visit): Promise<Response> {
  const flow = await core.sessions.readFlow(visit);

  if (!claim(flow.logouts, visit.url.searchParams.get("state") ?? "")) {
    return answer(
      visit,
      400,
      "invalid_state",
      "that sign-out is not one this browser started, or it expired",
    );
  }

  await core.sessions.writeFlow(visit, flow);

  return redirect(localPath(core.options.afterSignOut) ?? "/", visit.out);
}

async function backchannel(core: Core, visit: Visit): Promise<Response> {
  const client = await core.client(visit);

  if (!client)
    return answer(
      visit,
      400,
      "invalid_request",
      "this app has not shaken hands with masks",
      true,
    );

  const token = (await readForm(visit.request)).get("logout_token");

  if (!token)
    return answer(
      visit,
      400,
      "invalid_request",
      "logout_token is required",
      true,
    );

  let logout: LogoutToken;

  try {
    logout = await client.logoutToken(token);
  } catch (error) {
    if (error instanceof InvalidTokenError) {
      return answer(visit, 400, "invalid_request", describe(error), true);
    }

    throw error;
  }

  if (!(await acceptLogout(core.store, visit.issuerURL, logout, core.maxAge))) {
    return answer(
      visit,
      400,
      "invalid_request",
      "that logout token has already been used",
      true,
    );
  }

  if (core.options.onLogout) await core.options.onLogout(logout, visit.request);

  return new Response(null, {
    status: 200,
    headers: { "cache-control": "no-store" },
  });
}

export function handshakeHost(core: Core): HandshakeHost {
  return {
    handshakePath: core.handshakePath,
    credentials: core.credentials,
    async site(request) {
      const visit = await core.visit(request);

      return {
        origin: visit.origin,
        issuer: visit.issuerURL,
        cookies: visit.out,
      };
    },
    async issuer(request) {
      return core.issuers.get((await core.visit(request)).issuerURL);
    },
    async handshake(request) {
      return core.handshake(await core.visit(request));
    },
    privileges: core.privileges,
    manages: core.options.manages,
    async actor(request) {
      const visit = await core.visit(request);

      return core.masked(visit, await core.current(visit));
    },
    signInURL: (returnTo, privileges) =>
      core.loginURL({ returnTo, privilege: privileges }),
    async steppedUp(request, privileges) {
      return steppedUp(
        await core.sessions.readFlow(await core.visit(request)),
        privileges,
      );
    },
    async remember(request, state) {
      const visit = await core.visit(request);
      const flow = await core.sessions.readFlow(visit);

      flow.handshakes = keep(flow.handshakes, state, {
        until: now() + FLOW_LIFETIME,
        returnTo: core.returnTo(visit.url.searchParams.get("return_to")),
      });
      await core.sessions.writeFlow(visit, flow);

      return [];
    },
    async recall(request, state) {
      const visit = await core.visit(request);
      const flow = await core.sessions.readFlow(visit);
      const pending = claim(flow.handshakes, state);

      if (!pending) return { found: false, cookies: [] };

      await core.sessions.writeFlow(visit, flow);

      return { found: true, returnTo: pending.returnTo, cookies: [] };
    },
    async connected(request, returnTo) {
      const visit = await core.visit(request);

      return redirect(core.loginURL({ returnTo }), visit.out);
    },
    async disconnected(request) {
      await core.sessions.forget(await core.visit(request));
    },
  };
}
