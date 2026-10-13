import { organizationKey } from "../claims.js";
import type { Token } from "../client.js";
import { InvalidTokenError, MasksError, UnavailableError } from "../errors.js";
import { originOf } from "../handshake.js";
import type { IdTokenClaims, LogoutToken } from "../idtoken.js";
import { random } from "../key.js";
import { avatarResponse } from "./avatar.js";
import type { Core } from "./core.js";
import { answer, check, describe, refuseJSON } from "./guard.js";
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
import { escapeHTML, json, page, redirect, text } from "./responses.js";
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
        return await handshakeShow(core, visit);
      case "POST /handshake":
        return await handshakeCreate(core, visit);
      case "DELETE /handshake":
      case "POST /handshake/disconnect":
        return await handshakeDestroy(core, visit);
      case "GET /handshake/callback":
        return await handshakeCallback(core, visit);
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
  let client = await core.client(visit);

  if (client && !(await core.stillRegistered(visit, client.id))) {
    await core.disconnect(visit.request);
    client = await core.client(visit);
  }

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
      (await core.disconnect(visit.request))
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
  if (!(await core.configured(visit)))
    return refuseJSON(core, visit, "handshake_required");

  const masked = core.masked(visit, await core.current(visit));

  if (!masked.signedIn) return refuseJSON(core, visit, "login_required");

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
      authorization: `${data.tokens.token_type} ${data.tokens.access_token}`,
      size: visit.url.searchParams.get("size"),
      fetch: core.options.fetch ?? globalThis.fetch,
      limit: core.options.avatars,
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

async function handshakeShow(core: Core, visit: Visit): Promise<Response> {
  if (!(await core.configured(visit))) return beginHandshake(core, visit);

  const refused = await manager(core, visit);
  if (refused) return refused;

  return connectedPage(
    core.handshakePath,
    visit.issuerURL,
    Boolean(core.credentials.clear),
    visit.out,
  );
}

async function handshakeCreate(core: Core, visit: Visit): Promise<Response> {
  if (!sameOrigin(visit.request, visit.origin)) {
    return answer(
      visit,
      403,
      "forbidden",
      "a handshake is only started from this app",
    );
  }

  if (await core.configured(visit)) {
    const refused = await manager(core, visit);
    if (refused) return refused;
  }

  return beginHandshake(core, visit);
}

async function handshakeDestroy(core: Core, visit: Visit): Promise<Response> {
  if (!sameOrigin(visit.request, visit.origin)) {
    return answer(
      visit,
      403,
      "forbidden",
      "a disconnect is only asked for from this app",
    );
  }

  if (!(await core.configured(visit)))
    return redirect(core.handshakePath, visit.out, 303);

  const refused = await manager(core, visit);
  if (refused) return refused;

  if (!(await core.disconnect(visit.request))) {
    return answer(
      visit,
      400,
      "invalid_request",
      "the credential store cannot forget this connection",
    );
  }

  await core.sessions.forget(visit);

  if (wantsJSON(visit.request))
    return json(200, { connected: false }, visit.out);

  return redirect(core.handshakePath, visit.out, 303);
}

async function handshakeCallback(core: Core, visit: Visit): Promise<Response> {
  const params = visit.url.searchParams;
  const state = params.get("state") ?? "";
  const flow = await core.sessions.readFlow(visit);
  const pending = claim(flow.handshakes, state);

  if (!pending) {
    return answer(
      visit,
      400,
      "invalid_state",
      "that connection request is not one this browser started, or it expired",
    );
  }

  await core.sessions.writeFlow(visit, flow);

  if (await core.configured(visit)) {
    const refused = await manager(core, visit);
    if (refused) return refused;
  }

  if (!core.credentials.write) {
    return answer(
      visit,
      500,
      "handshake_unsaved",
      "the credential store cannot save this connection; set credentials to a store that writes",
    );
  }

  const handshake = await core.handshake(visit);
  const registration = await handshake.complete(params, state);

  await core.credentials.write(visit.request, {
    client_id: registration.client_id,
    client_secret: registration.client_secret,
    registration_access_token: registration.registration_access_token,
    registration_client_uri: registration.registration_client_uri,
  });

  return redirect(core.loginURL({ returnTo: pending.returnTo }), visit.out);
}

async function beginHandshake(core: Core, visit: Visit): Promise<Response> {
  const handshake = await core.handshake(visit);
  const started = handshake.start();
  const flow = await core.sessions.readFlow(visit);

  flow.handshakes = keep(flow.handshakes, started.state, {
    until: now() + FLOW_LIFETIME,
    returnTo: core.returnTo(visit.url.searchParams.get("return_to")),
  });
  await core.sessions.writeFlow(visit, flow);

  return redirect(started.url, visit.out, 303);
}

async function manager(
  core: Core,
  visit: Visit,
): Promise<Response | undefined> {
  const manages = core.options.manages;

  if (typeof manages === "string") {
    const outcome = await check(core, visit.request, {
      privileges: [manages],
      returnTo: core.handshakePath,
    });

    return outcome.response;
  }

  const masked = core.masked(visit, await core.current(visit));

  if (!masked.signedIn) {
    return redirect(
      core.loginURL({ returnTo: core.handshakePath }),
      visit.out,
      303,
    );
  }

  if (manages && (await manages(visit.request, masked)) === true)
    return undefined;

  return answer(
    visit,
    403,
    "forbidden",
    "only somebody this app lets manage its connection can reconnect or disconnect it",
  );
}

export function connectedPage(
  handshakePath: string,
  issuer: string,
  disconnects: boolean,
  cookies: string[],
): Response {
  const path = escapeHTML(handshakePath);
  const target = originOf(issuer);

  return page(
    "This app is connected",
    `<p>Reconnecting replaces the credentials it holds with a fresh pair. It is how you rotate them, and how you move this app to another account. No secret passes through your browser.</p>
<p>The app stops working between the approval and the moment it picks the new credentials up.</p>
<form method="post" action="${path}"><button type="submit">Reconnect it</button></form>
${disconnects ? `<form method="post" action="${path}/disconnect"><button type="submit">Disconnect it</button></form>` : ""}`,
    cookies,
    target ? [target] : [],
  );
}
