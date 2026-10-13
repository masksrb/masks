import assert from "node:assert/strict";
import { after, test } from "node:test";
import { Masks, memoryCredentials, memoryStore } from "../dist/index.js";
import { APP, Browser, SECRET, setup, signIn } from "./browser.js";
import { Fake } from "./fake.js";

const closers = [];

after(async () => {
  for (const close of closers) await close();
});

const json = { accept: "application/json" };

test("an app with no credentials shakes hands, then signs the person in", async () => {
  const held = await setup({ connected: false }, closers);
  const { fake, browser, credentials, masks } = held;

  const first = await browser.follow("/auth");
  assert.equal(first.status, 303);

  const handshake = new URL(first.headers.get("location"));
  assert.equal(handshake.origin + handshake.pathname, `${fake.url}/handshake`);
  assert.equal(handshake.searchParams.get("resource"), APP);
  assert.equal(handshake.searchParams.get("client_name"), "Catalog");
  assert.equal(
    handshake.searchParams.get("return_to"),
    `${APP}/auth/handshake/callback`,
  );
  assert.deepEqual(handshake.searchParams.getAll("redirect_uris"), [
    `${APP}/auth/callback`,
  ]);
  assert.equal(
    handshake.searchParams.get("backchannel_logout_uri"),
    `${APP}/auth/logout/backchannel`,
  );
  assert.equal(
    handshake.searchParams.get("post_logout_redirect_uri"),
    `${APP}/auth/logout/return`,
  );
  assert.equal(
    handshake.searchParams.get("scope"),
    "openid profile email offline_access",
  );

  const back = new URL(fake.shake(handshake.toString()));
  const toMasks = await browser.follow(`${back.pathname}${back.search}`);

  const saved = await credentials.read();
  assert.ok(saved.client_id.startsWith("app-"));
  assert.ok(saved.client_secret);
  assert.ok(saved.registration_access_token);

  const authorize = new URL(toMasks.headers.get("location"));
  assert.equal(authorize.searchParams.get("client_id"), saved.client_id);

  const back2 = new URL(fake.authorize(authorize.toString()));
  const done = await browser.follow(`${back2.pathname}${back2.search}`);
  assert.equal(done.status, 200);
  assert.deepEqual(await done.json(), { path: "/", signed_in: true });

  const person = await masks.peek(browser.request("/"));
  assert.equal(person.subject, "ada");
  assert.equal(person.name, "Ada Lovelace");
  assert.equal(person.organization.key, "acme");
  assert.equal(person.organizations.length, 2);
  assert.ok(person.role("owner"));
  assert.ok(person.accessToken);
  assert.deepEqual(await masks.connection(browser.request("/")), {
    connected: true,
    client_id: saved.client_id,
    issuer: fake.url,
  });
  assert.equal(await masks.registered(browser.request("/")), true);
});

test("the session cookie is sealed, httponly, lax, and secure on https", async () => {
  const held = await setup({ resource: "https://app.example.test" }, closers);
  const response = await signIn(held);

  assert.equal(response.status, 200);

  const names = [...held.browser.jar.keys()];
  assert.ok(names.some((name) => name.startsWith("__Host-masks")));

  const session = await held.browser.fetch("/auth/session", { headers: json });
  const body = await session.json();

  assert.equal(body.signed_in, true);
  assert.equal(body.subject, "ada");
  assert.equal(body.organization.key, "acme");
  assert.equal(body.avatar_url, "/auth/avatar");
  assert.equal(body.picture, "/auth/avatar");
  assert.equal(body.account_url, `${held.fake.url}/`);
  assert.equal(JSON.stringify(body).includes("eyJ"), false);
  assert.equal(session.headers.get("cache-control"), "no-store");

  for (const value of held.browser.jar.values()) {
    assert.doesNotMatch(value, /eyJ[\w-]*\.eyJ/);
  }

  const plain = await setup({}, closers);
  const started = await plain.browser.fetch("/auth");

  for (const line of started.headers.getSetCookie()) {
    assert.match(line, /HttpOnly/);
    assert.match(line, /SameSite=Lax/);
    assert.match(line, /Path=\//);
    assert.doesNotMatch(line, /;\s*Secure/i);
  }

  const secure = await held.browser.fetch("/auth");
  for (const line of secure.headers.getSetCookie()) {
    assert.match(line, /^__Host-/);
    assert.match(line, /;\s*Secure/i);
  }
});

test("a tampered or foreign cookie signs nobody in", async () => {
  const held = await setup({}, closers);
  await signIn(held);

  const [name, value] = [...held.browser.jar].find(([key]) => key === "masks");
  const flipped = value.slice(0, -2) + (value.endsWith("A") ? "BB" : "AA");

  const tampered = new Browser(held.browser.handler);
  tampered.jar.set(name, flipped);
  assert.equal((await held.masks.peek(tampered.request("/"))).signedIn, false);

  const other = new Masks({
    issuer: held.fake.url,
    resource: APP,
    secret: "another-secret-that-is-long-enough-12345",
    credentials: held.credentials,
  });
  assert.equal((await other.peek(held.browser.request("/"))).signedIn, false);

  const rotated = new Masks({
    issuer: held.fake.url,
    resource: APP,
    secret: ["another-secret-that-is-long-enough-12345", SECRET],
    credentials: held.credentials,
  });
  assert.equal((await rotated.peek(held.browser.request("/"))).signedIn, true);

  assert.throws(() => new Masks({ secret: "short" }), /32 characters/);
});

test("return_to is kept to this app's own paths", async () => {
  const held = await setup({}, closers);

  for (const [asked, landed] of [
    ["/reports?year=2026", "/reports"],
    ["/authors", "/authors"],
    ["/auth/session", "/"],
    ["https://evil.example/", "/"],
    ["//evil.example/", "/"],
    ["/\\evil.example", "/"],
    ["/%0d%0aLocation:x", "/%0d%0aLocation:x"],
  ]) {
    const browser = new Browser(held.browser.handler);
    const done = await signIn(
      { ...held, browser },
      {},
      `/auth?return_to=${encodeURIComponent(asked)}`,
    );

    assert.equal((await done.json()).path, landed, asked);
  }
});

test("several sign-ins can be in flight, and a stale one restarts once", async () => {
  const held = await setup({}, closers);
  const { browser, fake } = held;

  const first = (await browser.fetch("/auth")).headers.get("location");
  const second = (await browser.fetch("/auth")).headers.get("location");

  const back = new URL(fake.authorize(first));
  const done = await browser.follow(`${back.pathname}${back.search}`);
  assert.equal(done.status, 200);

  const fresh = new Browser(browser.handler);
  const stale = new URL(fake.authorize(second));
  const restarted = await fresh.fetch(`${stale.pathname}${stale.search}`);
  assert.equal(restarted.headers.get("location"), "/auth");

  const again = await fresh.fetch(`${stale.pathname}${stale.search}`);
  assert.equal(again.status, 400);
  assert.match(await again.text(), /invalid_state/);
});

test("the organization and a declined sign-in are passed through", async () => {
  const held = await setup(
    { masks: { organization: () => "globex" } },
    closers,
  );

  const started = await held.browser.fetch("/auth?organization=Acme");
  assert.equal(
    new URL(started.headers.get("location")).searchParams.get("organization"),
    "acme",
  );

  const fallback = await held.browser.fetch("/auth");
  assert.equal(
    new URL(fallback.headers.get("location")).searchParams.get("organization"),
    "globex",
  );

  const declined = new URL(
    held.fake.authorize(fallback.headers.get("location"), {
      error: "access_denied",
    }),
  );
  const answer = await held.browser.fetch(
    `${declined.pathname}${declined.search}`,
    { headers: json },
  );

  assert.equal(answer.status, 400);
  assert.equal((await answer.json()).error, "access_denied");
});

test("an expiring token is refreshed once for concurrent requests", async () => {
  const held = await setup({}, closers);
  held.fake.lifetime = 5;
  await signIn(held);

  held.fake.lifetime = 3600;
  held.fake.users.set("ada", { name: "Ada King" });

  const before = held.fake.tokenRequests.filter(
    (kind) => kind === "refresh_token",
  ).length;
  const [one, two] = await Promise.all([
    held.masks.masked(held.browser.request("/")),
    held.masks.masked(held.browser.request("/")),
  ]);

  assert.equal(
    held.fake.tokenRequests.filter((kind) => kind === "refresh_token").length,
    before + 1,
  );
  assert.ok(one.masked.signedIn);
  assert.ok(two.masked.signedIn);
  assert.equal(one.masked.name, "Ada King");
  assert.ok(one.cookies.length > 0);
  assert.equal(one.masked.accessToken, two.masked.accessToken);
});

test("servers that share a store refresh a session once between them", async () => {
  const store = memoryStore();
  const held = await setup({ masks: { store } }, closers);
  const other = new Masks({
    issuer: held.fake.url,
    resource: APP,
    secret: SECRET,
    credentials: held.credentials,
    store,
  });
  const flights = globalThis[Symbol.for("@masks/server v1 refreshes")];

  held.fake.lifetime = 5;
  await signIn(held);
  held.fake.lifetime = 3600;

  const before = held.fake.tokenRequests.filter(
    (kind) => kind === "refresh_token",
  ).length;
  const first = held.masks.masked(held.browser.request("/"));

  await new Promise((resolve) => setTimeout(resolve, 5));
  flights.clear();

  const waited = await other.masked(held.browser.request("/"));
  const done = await first;

  flights.clear();

  const later = await other.masked(held.browser.request("/"));

  assert.equal(
    held.fake.tokenRequests.filter((kind) => kind === "refresh_token").length,
    before + 1,
  );
  for (const answer of [done, waited, later]) {
    assert.ok(answer.masked.signedIn);
    assert.equal(answer.masked.accessToken, done.masked.accessToken);
  }
});

test("a refresh another server saw refused signs the session out here too", async () => {
  const store = memoryStore();
  const held = await setup({ masks: { store } }, closers);
  const other = new Masks({
    issuer: held.fake.url,
    resource: APP,
    secret: SECRET,
    credentials: held.credentials,
    store,
  });

  held.fake.lifetime = 5;
  await signIn(held);
  held.fake.refreshRefusal = { status: 400, code: "invalid_grant" };

  assert.equal(
    (await held.masks.masked(held.browser.request("/"))).masked.signedIn,
    false,
  );

  held.fake.refreshRefusal = undefined;

  const { masked, cookies } = await other.masked(held.browser.request("/"));

  assert.equal(masked.signedIn, false);
  assert.ok(cookies.some((line) => /^masks=; .*Max-Age=0/.test(line)));
  assert.equal(
    held.fake.tokenRequests.filter((kind) => kind === "refresh_token").length,
    1,
  );
});

test("a logout the store cannot record answers 503, and masks can send it again", async () => {
  const kept = memoryStore();
  let failing = true;
  const store = {
    ...kept,
    set(key, value, expiresIn) {
      if (failing) throw new Error("the store is down");
      return kept.set(key, value, expiresIn);
    },
  };
  const held = await setup({ masks: { store } }, closers);
  await signIn(held, { sid: "session-1" });

  const token = await held.fake.logoutToken({ aud: "app", sid: "session-1" });
  const post = () =>
    held.browser.fetch("/auth/logout/backchannel", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ logout_token: token }).toString(),
    });

  assert.equal((await post()).status, 503);
  assert.equal(
    (await held.masks.peek(held.browser.request("/"))).signedIn,
    true,
  );

  failing = false;

  assert.equal((await post()).status, 200);
  assert.equal((await post()).status, 400);
  assert.equal(
    (await held.masks.peek(held.browser.request("/"))).signedIn,
    false,
  );
});

test("a refused refresh forgets the session", async () => {
  const held = await setup({}, closers);
  held.fake.lifetime = 5;
  await signIn(held);
  held.fake.refreshRefusal = { status: 400, code: "invalid_grant" };

  const { masked, cookies } = await held.masks.masked(
    held.browser.request("/"),
  );

  assert.equal(masked.signedIn, false);
  assert.ok(cookies.some((line) => /^masks=; .*Max-Age=0/.test(line)));
});

test("an unavailable refresh keeps the session for later", async () => {
  const held = await setup({}, closers);
  held.fake.lifetime = 5;
  await signIn(held);
  held.fake.refreshRefusal = { status: 503, code: "temporarily_unavailable" };

  const { masked, cookies } = await held.masks.masked(
    held.browser.request("/"),
  );

  assert.equal(masked.signedIn, false);
  assert.equal(cookies.length, 0);
});

test("signing out revokes the refresh token and refuses other sites", async () => {
  const held = await setup({}, closers);
  await signIn(held);

  const forged = await held.browser.fetch("/auth/logout", {
    method: "POST",
    headers: { origin: "https://evil.example", "sec-fetch-site": "cross-site" },
  });
  assert.equal(forged.status, 403);
  assert.equal(
    (await held.masks.peek(held.browser.request("/"))).signedIn,
    true,
  );

  const out = await held.browser.fetch("/auth/logout", {
    method: "POST",
    headers: { origin: APP, "sec-fetch-site": "same-origin" },
  });

  assert.equal(out.status, 303);
  assert.equal(out.headers.get("location"), "/");
  assert.equal(held.fake.revoked.length, 1);
  assert.equal(
    (await held.masks.peek(held.browser.request("/"))).signedIn,
    false,
  );
});

test("signing out everywhere comes back once through the logout return", async () => {
  const held = await setup({ masks: { afterSignOut: "/bye" } }, closers);
  await signIn(held);

  const out = await held.browser.fetch("/auth/logout?everywhere=1", {
    method: "DELETE",
    headers: json,
  });
  const { logout_url, signed_in } = await out.json();
  const upstream = new URL(logout_url);

  assert.equal(signed_in, false);
  assert.equal(upstream.origin + upstream.pathname, `${held.fake.url}/logout`);
  assert.equal(upstream.searchParams.get("client_id"), "app");
  assert.equal(
    upstream.searchParams.get("post_logout_redirect_uri"),
    `${APP}/auth/logout/return`,
  );

  const path = `/auth/logout/return?state=${upstream.searchParams.get("state")}`;
  const landed = await held.browser.fetch(path);
  assert.equal(landed.headers.get("location"), "/bye");

  const reused = await held.browser.fetch(path);
  assert.equal(reused.status, 400);
  assert.equal(
    (await held.browser.fetch("/auth/logout/return?state=forged")).status,
    400,
  );
  assert.equal(
    (
      await held.browser.fetch(
        `/auth/handshake/callback?state=${upstream.searchParams.get("state")}`,
      )
    ).status,
    400,
  );
});

test("a back-channel logout ends the session it names", async () => {
  const store = memoryStore();
  const heard = [];
  const held = await setup(
    { masks: { store, onLogout: (logout) => heard.push(logout.sid) } },
    closers,
  );
  await signIn(held, { sid: "session-1" });

  const other = new Browser(held.browser.handler);
  await signIn({ ...held, browser: other }, { sid: "session-2" });

  const refused = await held.browser.fetch("/auth/logout/backchannel", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: "logout_token=nonsense",
  });
  assert.equal(refused.status, 400);

  const flooded = await held.browser.fetch("/auth/logout/backchannel", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: `logout_token=${"a".repeat(70 * 1024)}`,
  });
  assert.equal(flooded.status, 400);
  assert.match(await flooded.text(), /larger than 64 KiB/);

  const token = await held.fake.logoutToken({ aud: "app", sid: "session-1" });
  const heardIt = await held.browser.fetch("/auth/logout/backchannel", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ logout_token: token }).toString(),
  });

  assert.equal(heardIt.status, 200);
  assert.deepEqual(heard, ["session-1"]);
  assert.equal(
    (await held.masks.peek(held.browser.request("/"))).signedIn,
    false,
  );
  assert.equal((await held.masks.peek(other.request("/"))).signedIn, true);

  await new Promise((resolve) => setTimeout(resolve, 1100));
  const everyone = await held.fake.logoutToken({ aud: "app", sub: "ada" });
  await held.browser.fetch("/auth/logout/backchannel", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ logout_token: everyone }).toString(),
  });

  assert.equal((await held.masks.peek(other.request("/"))).signedIn, false);
});

test("a privilege sends the person through masks once, then refuses", async () => {
  const held = await setup(
    {
      masks: {
        privileges: {
          admin: ["catalog:admin"],
          billing: { role: ["billing"] },
          globex: { organization: "globex" },
        },
      },
    },
    closers,
  );
  await signIn(held);

  const request = () => held.browser.request("/settings?tab=2");
  const first = await held.masks.require(request(), "admin");

  const login = first.refusal.toResponse().headers.get("location");
  assert.equal(login, "/auth?return_to=%2Fsettings%3Ftab%3D2&privilege=admin");

  const started = await held.browser.fetch(login);
  const authorize = new URL(started.headers.get("location"));
  assert.equal(
    authorize.searchParams.get("scope"),
    "openid profile email offline_access catalog:admin",
  );

  const back = new URL(
    held.fake.authorize(authorize.toString(), {
      scope: "openid profile email offline_access",
    }),
  );
  await held.browser.fetch(`${back.pathname}${back.search}`);

  const second = await held.masks.require(request(), "admin");
  assert.equal(second.refusal.toResponse().status, 403);
  assert.match(await second.refusal.toResponse().text(), /insufficient_scope/);

  const fetched = await held.masks.require(
    held.browser.request("/settings", { headers: json }),
    "billing",
  );
  assert.equal(fetched.refusal.toResponse().status, 403);
  assert.equal(
    (await fetched.refusal.toResponse().json()).error,
    "insufficient_role",
  );

  const elsewhere = await held.masks.require(request(), "globex");
  assert.equal(
    (await elsewhere.refusal.toResponse().text()).startsWith(
      "insufficient_organization",
    ),
    true,
  );

  const fine = await held.masks.require(request());
  assert.ok(fine.masked.signedIn);
  assert.deepEqual(fine.masked.privileges, []);
  assert.throws(
    () => held.masks.loginURL({ privilege: "nope" }),
    /no privilege/,
  );
});

test("a JSON request for a missing privilege gets 403 with the login URL", async () => {
  const held = await setup(
    { masks: { privileges: { admin: ["catalog:admin"] } } },
    closers,
  );
  await signIn(held);

  const answer = await held.masks.require(
    held.browser.request("/api/things", {
      headers: { ...json, referer: `${APP}/things` },
    }),
    "admin",
  );
  const body = await answer.refusal.toResponse().json();

  assert.equal(answer.refusal.toResponse().status, 403);
  assert.equal(body.error, "privilege_required");
  assert.deepEqual(body.privileges, ["admin"]);
  assert.equal(
    body.login_url,
    "/auth?return_to=%2Fapi%2Fthings&privilege=admin",
  );

  const signedOut = new Browser(held.browser.handler);
  const refused = await held.masks.require(
    signedOut.request("/api/things", { headers: json }),
  );

  assert.equal(refused.refusal.toResponse().status, 401);
  assert.equal(
    (await refused.refusal.toResponse().json()).error,
    "login_required",
  );

  const page = await held.masks.require(signedOut.request("/things"));
  assert.equal(
    page.refusal.toResponse().headers.get("location"),
    "/auth?return_to=%2Fthings",
  );
});

test("a refusal names its kind and where a browser goes, whatever the request accepts", async () => {
  const held = await setup(
    { masks: { privileges: { admin: ["catalog:admin"] } } },
    closers,
  );
  const signedOut = await held.masks.require(
    held.browser.request("/reports", { headers: json }),
  );

  assert.equal(signedOut.refusal.kind, "login");
  assert.equal(signedOut.refusal.url, "/auth?return_to=%2Freports");
  assert.equal(signedOut.refusal.toResponse().status, 401);
  assert.equal(
    signedOut.refusal
      .toResponse(held.browser.request("/reports"))
      .headers.get("location"),
    "/auth?return_to=%2Freports",
  );

  await signIn(held);

  const stepUp = await held.masks.require(
    held.browser.request("/admin", { headers: json }),
    "admin",
  );

  assert.equal(stepUp.refusal.kind, "step_up");
  assert.equal(stepUp.refusal.url, "/auth?return_to=%2Fadmin&privilege=admin");
  assert.equal(stepUp.refusal.toResponse().status, 403);

  const unconnected = await setup({ connected: false }, closers);
  const handshake = await unconnected.masks.require(
    unconnected.browser.request("/reports", { headers: json }),
  );

  assert.equal(handshake.refusal.kind, "handshake");
  assert.equal(handshake.refusal.url, "/auth/handshake?return_to=%2Freports");
});

test("an API checks bearer tokens by scope, role, and organization", async () => {
  const held = await setup(
    {
      masks: {
        resourceScopes: ["catalog:read"],
        privileges: { read: ["catalog:read"], owner: { role: "owner" } },
      },
    },
    closers,
  );
  const { fake, masks } = held;
  const token = await fake.accessToken("ada", "catalog:read", undefined, {
    aud: APP,
    org: { id: "o-1", key: "acme", role: "member" },
  });
  const call = (authorization) =>
    new Request(`${APP}/api/catalog`, {
      headers: authorization ? { authorization } : {},
    });

  const ok = await masks.protect(call(`Bearer ${token}`), "read");
  assert.equal(ok.masked.subject, "ada");
  assert.ok(ok.masked.permits("catalog:read"));

  const none = await masks.protect(call(), "read");
  assert.equal(none.refusal.kind, "invalid_token");
  assert.equal(none.refusal.toResponse().status, 401);
  assert.match(
    none.refusal.toResponse().headers.get("www-authenticate"),
    new RegExp(
      `resource_metadata="${APP}/.well-known/oauth-protected-resource"`,
    ),
  );

  const role = await masks.protect(call(`Bearer ${token}`), "owner");
  assert.equal(role.refusal.kind, "forbidden");
  assert.equal(role.refusal.error.code, "insufficient_role");
  assert.equal(role.refusal.toResponse().status, 403);
  assert.match(
    role.refusal.toResponse().headers.get("www-authenticate"),
    /insufficient_role/,
  );

  const narrow = await fake.accessToken("ada", "other", undefined, {
    aud: APP,
  });
  const scope = await masks.protect(call(`Bearer ${narrow}`), "read");
  assert.equal(scope.refusal.toResponse().status, 403);
  assert.match(
    scope.refusal.toResponse().headers.get("www-authenticate"),
    /error="insufficient_scope".*scope="catalog:read"/,
  );
  assert.match(
    scope.refusal.toResponse().headers.get("www-authenticate"),
    /DPoP error="insufficient_scope".*resource_metadata=.*algs="ES256/,
  );

  const elsewhere = await fake.accessToken("ada", "catalog:read", undefined, {
    aud: "https://other.example",
  });
  assert.equal(
    (
      await masks.protect(call(`Bearer ${elsewhere}`), "read")
    ).refusal.toResponse().status,
    401,
  );

  const metadata = await masks.handle(
    new Request(`${APP}/.well-known/oauth-protected-resource`),
  );
  assert.deepEqual(await metadata.json(), {
    resource: APP,
    authorization_servers: [fake.url],
    bearer_methods_supported: ["header"],
    dpop_signing_alg_values_supported: [
      "ES256",
      "ES384",
      "ES512",
      "PS256",
      "PS384",
      "PS512",
      "RS256",
    ],
    scopes_supported: ["catalog:read"],
  });

  const broken = new Masks({
    issuer: "http://127.0.0.1:1",
    resource: APP,
    secret: SECRET,
    credentials: memoryCredentials(),
  });
  const unavailable = await broken.protect(call(`Bearer ${token}`));
  assert.equal(unavailable.refusal.toResponse().status, 503);
  assert.equal(
    unavailable.refusal.toResponse().headers.get("www-authenticate"),
    null,
  );
});

test("guard reads a bearer token when one is sent and the session otherwise", async () => {
  const held = await setup({}, closers);
  await signIn(held);

  const bySession = await held.masks.guard(held.browser.request("/x"));
  assert.ok(bySession.masked.signedIn);

  const byToken = await held.masks.guard(
    new Request(`${APP}/x`, { headers: { authorization: "Bearer nonsense" } }),
  );
  assert.equal(byToken.refusal.toResponse().status, 401);
});

test("the avatar comes through this app with the person's token", async () => {
  const held = await setup({}, closers);
  await signIn(held);

  const photo = await held.browser.fetch("/auth/avatar?size=100");
  assert.equal(photo.status, 200);
  assert.equal(photo.headers.get("content-type"), "image/png");
  assert.equal(await photo.text(), "png-bytes");
  assert.match(held.fake.avatarAsks.at(-1), /size=128/);

  held.fake.avatarType = "text/html";
  assert.equal((await held.browser.fetch("/auth/avatar")).status, 404);

  held.fake.avatarType = "image/png";
  held.fake.avatarBody = Buffer.alloc(64);
  const small = new Masks({
    issuer: held.fake.url,
    resource: APP,
    secret: SECRET,
    credentials: held.credentials,
    avatars: { bytes: 16 },
  });
  const capped = await small.handle(held.browser.request("/auth/avatar"));
  await assert.rejects(capped.arrayBuffer());

  held.fake.avatarRedirect = "http://elsewhere.example/a.png";
  assert.equal((await held.browser.fetch("/auth/avatar")).status, 404);

  const signedOut = new Browser(held.browser.handler);
  assert.equal((await signedOut.fetch("/auth/avatar")).status, 404);
});

test("only a manager reconnects or disconnects a connected app", async () => {
  const held = await setup(
    {
      masks: {
        privileges: { admin: { role: "owner" } },
        manages: "admin",
      },
    },
    closers,
  );

  const signedOut = await held.browser.fetch("/auth/handshake");
  assert.equal(signedOut.status, 302);
  assert.equal(
    signedOut.headers.get("location"),
    "/auth?return_to=%2Fauth%2Fhandshake",
  );

  await signIn(held);
  const shown = await held.browser.fetch("/auth/handshake");
  assert.equal(shown.status, 200);
  assert.match(await shown.text(), /Reconnect it/);
  assert.match(
    shown.headers.get("content-security-policy"),
    new RegExp(`form-action 'self' ${held.fake.url};`),
  );

  const forged = await held.browser.fetch("/auth/handshake/disconnect", {
    method: "POST",
    headers: { "sec-fetch-site": "cross-site" },
  });
  assert.equal(forged.status, 403);

  const reconnect = await held.browser.fetch("/auth/handshake", {
    method: "POST",
    headers: { origin: APP },
  });
  assert.equal(reconnect.status, 303);
  assert.ok(
    reconnect.headers.get("location").startsWith(`${held.fake.url}/handshake`),
  );

  const gone = await held.browser.fetch("/auth/handshake/disconnect", {
    method: "POST",
    headers: { origin: APP },
  });
  assert.equal(gone.status, 303);
  assert.equal(await held.credentials.read(), undefined);

  const member = await setup(
    { masks: { privileges: { admin: { role: "billing" } }, manages: "admin" } },
    closers,
  );
  await signIn(member);
  assert.equal((await member.browser.fetch("/auth/handshake")).status, 403);

  const scoped = await setup(
    { masks: { privileges: { admin: ["catalog:admin"] }, manages: "admin" } },
    closers,
  );
  await signIn(scoped);
  const asked = await scoped.browser.fetch("/auth/handshake");
  assert.equal(asked.status, 302);
  assert.equal(
    asked.headers.get("location"),
    "/auth?return_to=%2Fauth%2Fhandshake&privilege=admin",
  );

  const back = await signIn(scoped, {}, asked.headers.get("location"));
  assert.equal(back.status, 200);
  assert.match(await back.text(), /Reconnect it/);
});

test("a session store keeps the tokens server-side and rotates the id on sign-in", async () => {
  const kept = memoryStore();
  const written = [];
  const sessions = {
    ...kept,
    set(key, value, expiresIn) {
      written.push(key, value);
      return kept.set(key, value, expiresIn);
    },
  };
  const held = await setup({ masks: { sessions } }, closers);
  await signIn(held);

  const { accessToken, subject } = await held.masks.peek(
    held.browser.request("/"),
  );
  assert.ok(written.length > 0);
  for (const value of written) {
    assert.ok(!value.includes(accessToken));
    assert.ok(!value.includes(subject));
  }

  const first = held.browser.jar.get("masks");
  assert.ok(first.length < 200);

  await signIn(held);
  const second = held.browser.jar.get("masks");
  assert.notEqual(first, second);

  const replay = new Browser(held.browser.handler);
  replay.jar.set("masks", first);
  assert.equal((await held.masks.peek(replay.request("/"))).signedIn, false);
  assert.equal(
    (await held.masks.peek(held.browser.request("/"))).signedIn,
    true,
  );
});

test("signed out, the session route answers 401 with where to go", async () => {
  const held = await setup({}, closers);
  const answer = await held.browser.fetch("/auth/session", { headers: json });

  assert.equal(answer.status, 401);
  assert.deepEqual(await answer.json(), {
    signed_in: false,
    error: "login_required",
    login_url: "/auth",
  });

  const unconfigured = await setup({ connected: false }, closers);
  const handshake = await unconfigured.browser.fetch("/auth/session", {
    headers: json,
  });

  assert.equal((await handshake.json()).error, "handshake_required");
});

test("a provider connection goes through the app's own client", async () => {
  const held = await setup(
    { masks: { delegations: "/connect/callback" } },
    closers,
  );
  const delegations = await held.masks.delegations(held.browser.request("/"));

  assert.equal(delegations.redirectURI, `${APP}/connect/callback`);

  const started = await delegations.start({ provider: "google" });
  const connection = await delegations.finish(
    new URL(held.fake.authorize(started.url)),
    started,
  );

  assert.equal(connection.connection, "connection-google");
});

test("an app masks no longer knows shakes hands again", async () => {
  const held = await setup({ connected: false }, closers);
  const first = await held.browser.fetch("/auth/handshake");
  const back = new URL(held.fake.shake(first.headers.get("location")));
  await held.browser.fetch(`${back.pathname}${back.search}`);

  const saved = await held.credentials.read();
  held.fake.registrations.delete(saved.client_id);

  assert.equal(await held.masks.registered(held.browser.request("/")), false);

  const again = await held.browser.fetch("/auth");
  assert.equal(again.headers.get("location"), "/auth/handshake");
  assert.equal(await held.credentials.read(), undefined);
});

test("a provider connection is finished only by the person who started it", async () => {
  const held = await setup(
    { masks: { delegations: "/connect/callback" } },
    closers,
  );
  await signIn(held);

  const started = await held.masks.startDelegation(
    held.browser.request("/connect"),
    "google",
  );
  held.browser.keep(started);
  const back = new URL(held.fake.authorize(started.headers.get("location")));
  const { connection, cookies } = await held.masks.finishDelegation(
    held.browser.request(`${back.pathname}${back.search}`),
  );

  assert.equal(connection.connection, "connection-google");
  assert.equal(connection.account, "ada");
  assert.ok(cookies.length > 0);

  const again = await held.masks.startDelegation(
    held.browser.request("/connect"),
    "google",
  );
  held.browser.keep(again);
  const someoneElse = new URL(
    held.fake.authorize(again.headers.get("location"), { sub: "eve" }),
  );
  await assert.rejects(
    held.masks.finishDelegation(
      held.browser.request(`${someoneElse.pathname}${someoneElse.search}`),
    ),
    (error) => error.code === "access_denied",
  );

  const stranger = new Browser(held.browser.handler);
  await assert.rejects(
    held.masks.finishDelegation(
      stranger.request(`${back.pathname}${back.search}`),
    ),
    (error) => error.code === "invalid_state",
  );

  const signedOut = await held.masks.startDelegation(
    stranger.request("/connect"),
    "google",
  );
  assert.equal(signedOut.headers.get("location"), "/auth?return_to=%2Fconnect");
});

test("a subject-wide logout in the second of the sign-in still ends it, and a logout token is used once", async () => {
  const held = await setup({}, closers);
  await signIn(held, { sid: "s-now" });

  const token = await held.fake.logoutToken({ aud: "app", sub: "ada" });
  const send = () =>
    held.browser.fetch("/auth/logout/backchannel", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ logout_token: token }).toString(),
    });

  assert.equal((await send()).status, 200);
  assert.equal(
    (await held.masks.peek(held.browser.request("/"))).signedIn,
    false,
  );

  const again = await send();
  assert.equal(again.status, 400);
  assert.match((await again.json()).error_description, /already been used/);
});

test("a credential store that cannot write refuses the handshake before masks registers anything", async () => {
  const held = await setup({ credentials: { read: () => undefined } }, closers);
  const first = await held.browser.fetch("/auth/handshake");
  const before = held.fake.clients.size;
  const back = new URL(held.fake.shake(first.headers.get("location")));
  const answer = await held.browser.fetch(`${back.pathname}${back.search}`);

  assert.equal(answer.status, 500);
  assert.match(await answer.text(), /handshake_unsaved/);
  assert.equal(held.fake.clients.size, before);
  assert.equal(held.fake.initial.size, 1);
});

test("a session another issuer signed in is not honored", async () => {
  const held = await setup({}, closers);
  await signIn(held);

  const json = { accept: "application/json" };
  const here = await held.browser.fetch("/auth/session", { headers: json });
  assert.equal((await here.json()).signed_in, true);

  const other = await Fake.start();
  closers.push(other.close);
  const elsewhere = new Masks({
    issuer: other.url,
    resource: APP,
    secret: SECRET,
    credentials: held.credentials,
  });
  const answer = await elsewhere.handle(
    held.browser.request("/auth/session", { headers: json }),
  );

  assert.equal((await answer.json()).signed_in, false);
});

test("a browser on an unconnected app is sent to connect it, and an API client is refused", async () => {
  const held = await setup({ connected: false }, closers);
  const page = await held.masks.guard(
    held.browser.request("/dashboard", { headers: { accept: "text/html" } }),
  );

  assert.equal(page.refusal.toResponse().status, 302);
  assert.equal(
    page.refusal.toResponse().headers.get("location"),
    "/auth/handshake?return_to=%2Fdashboard",
  );

  const api = await held.masks.guard(
    held.browser.request("/api/items", {
      headers: { accept: "application/json" },
    }),
  );

  assert.equal(api.refusal.toResponse().status, 401);
});

test("the first sign-in on an unconnected app comes back to its page after the handshake", async () => {
  const held = await setup({ connected: false }, closers);
  const first = await held.browser.fetch("/auth?return_to=/dashboard");

  assert.equal(
    first.headers.get("location"),
    "/auth/handshake?return_to=%2Fdashboard",
  );

  const shaking = await held.browser.fetch(first.headers.get("location"));
  const back = new URL(held.fake.shake(shaking.headers.get("location")));
  const connected = await held.browser.fetch(`${back.pathname}${back.search}`);

  assert.equal(
    connected.headers.get("location"),
    "/auth?return_to=%2Fdashboard",
  );
});

test("a path masks does not own is passed on without resolving the issuer", async () => {
  let resolved = 0;
  const masks = new Masks({
    issuer: () => {
      resolved += 1;
      return "http://127.0.0.1:1";
    },
    resource: APP,
    secret: SECRET,
    credentials: memoryCredentials(),
  });

  assert.equal(await masks.handle(new Request(`${APP}/catalog`)), undefined);
  assert.equal(resolved, 0);
});

test("sign-ins a minute apart check that masks still knows the app once", async () => {
  const held = await setup({ connected: false }, closers);
  const shaking = await held.browser.fetch("/auth/handshake");
  const back = new URL(held.fake.shake(shaking.headers.get("location")));
  await held.browser.fetch(`${back.pathname}${back.search}`);

  const before = held.fake.registrationReads;
  const first = await held.browser.fetch("/auth");
  const second = await held.browser.fetch("/auth");

  assert.ok(first.headers.get("location").startsWith(held.fake.url));
  assert.ok(second.headers.get("location").startsWith(held.fake.url));
  assert.equal(held.fake.registrationReads - before, 1);
});
