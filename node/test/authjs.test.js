import assert from "node:assert/strict";
import { after, test } from "node:test";
import { NextRequest } from "next/server";
import NextAuth from "next-auth";
import { masksAuth } from "../dist/authjs.js";
import { memoryCredentials } from "../dist/index.js";
import { APP, Browser } from "./browser.js";
import { Fake } from "./fake.js";

const closers = [];

after(async () => {
  for (const close of closers) await close();
});

const SECRET = "an-auth-js-secret-that-is-long-enough-1234";

async function setup(options = {}) {
  const fake = await Fake.start();
  closers.push(fake.close);

  const credentials = options.credentials ?? memoryCredentials();
  const auth = masksAuth(NextAuth, {
    issuer: fake.url,
    resource: APP,
    secret: SECRET,
    trustHost: true,
    credentials,
    name: "Catalog",
    privileges: { admin: ["catalog:admin"], owner: { role: "owner" } },
    manages: "owner",
    ...options.masks,
  });
  const handler = async (request) =>
    request.method === "POST"
      ? auth.handlers.POST(request)
      : auth.handlers.GET(request);

  return { fake, auth, credentials, browser: new Browser(handler, APP) };
}

async function throughMasks(held, response, options = {}) {
  const { fake, browser } = held;
  let answer = response;

  for (let hop = 0; hop < 10; hop++) {
    const location = answer.headers.get("location");

    if (!location) return answer;

    const next = new URL(location, APP);

    if (next.origin === fake.url && next.pathname === "/handshake") {
      const back = new URL(fake.shake(next.toString()));
      answer = await browser.fetch(`${back.pathname}${back.search}`);
    } else if (next.origin === fake.url && next.pathname === "/authorize") {
      const back = new URL(fake.authorize(next.toString(), options));
      answer = await browser.fetch(`${back.pathname}${back.search}`);
    } else if (next.origin === APP && next.pathname.startsWith("/api/auth/")) {
      answer = await browser.fetch(`${next.pathname}${next.search}`);
    } else {
      return answer;
    }

    if (answer.status < 300 || answer.status >= 400) return answer;
  }

  return answer;
}

async function signedIn(options = {}) {
  const held = await setup(options);
  options.before?.(held.fake);
  const started = await held.browser.fetch(
    "/api/auth/masks/signin?callbackUrl=/dashboard",
  );
  const landed = await throughMasks(held, started, options.authorize);

  return { ...held, landed };
}

async function session(browser) {
  const answer = await browser.fetch("/api/auth/session", {
    headers: { accept: "application/json" },
  });

  return answer.json();
}

test("an unconnected app shakes hands, then signs the person in where they started", async () => {
  const held = await signedIn();
  const { fake, browser, credentials, landed } = held;

  assert.equal(landed.status, 302);
  assert.equal(landed.headers.get("location"), `${APP}/dashboard`);

  const asked = fake.handshakes[0];
  assert.equal(asked.get("resource"), APP);
  assert.equal(asked.get("client_name"), "Catalog");
  assert.deepEqual(asked.getAll("redirect_uris"), [
    `${APP}/api/auth/callback/masks`,
  ]);
  assert.equal(
    asked.get("return_to"),
    `${APP}/api/auth/masks/handshake/callback`,
  );
  assert.equal(
    asked.get("backchannel_logout_uri"),
    `${APP}/api/auth/masks/logout/backchannel`,
  );
  assert.equal(
    asked.get("scope"),
    "openid profile email offline_access catalog:admin",
  );

  const saved = await credentials.read(new Request(APP));
  assert.match(saved.client_id, /^app-/);
  assert.ok(saved.client_secret);

  const authorized = fake.authorized;
  assert.equal(authorized.get("scope"), "openid profile email offline_access");
  assert.equal(authorized.get("resource"), APP);
  assert.ok(authorized.get("nonce"));
  assert.equal(authorized.get("code_challenge_method"), "S256");

  const found = await session(browser);

  assert.equal(found.user.id, "ada");
  assert.equal(found.user.name, "Ada Lovelace");
  assert.equal(found.masks.subject, "ada");
  assert.equal(found.masks.organization.key, "acme");
  assert.deepEqual(found.masks.privileges, ["owner"]);
  assert.equal(found.masks.tenant.name, "Acme");
  assert.equal(found.access_token, undefined);
  assert.doesNotMatch(JSON.stringify(found), /eyJ/);
});

test("a stale handshake callback is refused", async () => {
  const held = await setup();
  const answer = await held.browser.fetch(
    "/api/auth/masks/handshake/callback?state=forged&initial_access_token=x",
  );

  assert.equal(answer.status, 400);
  assert.match(await answer.text(), /invalid_state/);
});

test("an expired access token is refreshed once, however many requests arrive together", async () => {
  const held = await signedIn({
    before: (fake) => {
      fake.lifetime = 1;
    },
  });
  const { fake, browser } = held;

  fake.lifetime = 3600;

  const expiring = fake.tokenRequests.length;

  const answers = await Promise.all(
    Array.from({ length: 5 }, () => session(browser)),
  );
  const refreshes = fake.tokenRequests
    .slice(expiring)
    .filter((grant) => grant === "refresh_token");

  assert.equal(refreshes.length, 1);

  for (const answer of answers) assert.equal(answer.masks.subject, "ada");
});

test("a back-channel logout ends the session, and its token is used once", async () => {
  const held = await signedIn({ authorize: { sid: "sid-1" } });
  const { fake, browser, credentials } = held;
  const { client_id } = await credentials.read(new Request(APP));
  const token = await fake.logoutToken({ aud: client_id, sid: "sid-1" });
  const post = () =>
    browser.fetch("/api/auth/masks/logout/backchannel", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ logout_token: token }),
    });

  assert.equal((await post()).status, 200);
  assert.equal((await post()).status, 400);
  assert.equal(await session(browser), null);
});

test("signing in for a privilege asks masks for its scopes", async () => {
  const held = await signedIn();
  const { fake, browser } = held;
  const started = await browser.fetch(
    "/api/auth/masks/signin?privilege=admin&callbackUrl=/admin",
  );

  await throughMasks(held, started);

  assert.equal(
    fake.authorized.get("scope"),
    "openid profile email offline_access catalog:admin",
  );
  assert.ok(browser.jar.has("masks-stepped"));
});

test("only a manager sees the connection, and a cross-site disconnect is refused", async () => {
  const held = await signedIn();
  const { browser } = held;

  const shown = await browser.fetch("/api/auth/masks/handshake");
  assert.equal(shown.status, 200);
  assert.match(await shown.text(), /This app is connected/);
  assert.match(
    shown.headers.get("content-security-policy"),
    new RegExp(`form-action 'self' ${held.fake.url};`),
  );

  const forged = await browser.fetch("/api/auth/masks/handshake/disconnect", {
    method: "POST",
    headers: { "sec-fetch-site": "cross-site" },
  });
  assert.equal(forged.status, 403);
});

test("a manager who signed in without the managing scopes is asked for them once", async () => {
  const held = await signedIn({ masks: { manages: "admin" } });
  const { fake, browser } = held;
  const first = await browser.fetch("/api/auth/masks/handshake");

  assert.equal(first.status, 303);
  assert.equal(
    first.headers.get("location"),
    "/api/auth/masks/signin?callbackUrl=%2Fapi%2Fauth%2Fmasks%2Fhandshake&privilege=admin",
  );

  const declined = await throughMasks(
    held,
    await browser.fetch(first.headers.get("location")),
    { scope: "openid profile email offline_access" },
  );
  assert.equal(declined.status, 403);

  const granted = await throughMasks(
    held,
    await browser.fetch(first.headers.get("location")),
  );
  assert.equal(
    fake.authorized.get("scope"),
    "openid profile email offline_access catalog:admin",
  );
  assert.equal(granted.status, 200);
});

test("somebody who does not manage the app cannot see or change its connection", async () => {
  const held = await signedIn({
    authorize: { sub: "bob" },
    before: (fake) =>
      fake.users.set("bob", {
        name: "Bob",
        org: { id: "o-2", key: "globex", name: "Globex", role: "member" },
      }),
  });
  const shown = await held.browser.fetch("/api/auth/masks/handshake");

  assert.equal(shown.status, 403);
});

test("a second copy of auth.ts, as Next loads one for its proxy, shares the connection, the refresh, and logouts", async () => {
  const { mkdtemp, rm } = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const { fileCredentials } = await import("../dist/index.js");
  const directory = await mkdtemp(join(tmpdir(), "masks-authjs-"));
  closers.push(() => rm(directory, { recursive: true, force: true }));

  const path = join(directory, "masks.json");
  const held = await signedIn({
    credentials: fileCredentials(path),
    before: (fake) => {
      fake.lifetime = 1;
    },
  });
  const { fake, browser } = held;
  const proxy = masksAuth(NextAuth, {
    issuer: fake.url,
    resource: APP,
    secret: SECRET,
    trustHost: true,
    credentials: fileCredentials(path),
  });
  const other = new Browser((request) => proxy.handlers.GET(request), APP);

  other.jar = browser.jar;
  fake.lifetime = 3600;

  const before = fake.tokenRequests.length;
  const answers = await Promise.all([
    session(browser),
    session(other),
    session(browser),
    session(other),
  ]);
  const refreshes = fake.tokenRequests
    .slice(before)
    .filter((grant) => grant === "refresh_token");

  assert.equal(refreshes.length, 1);
  for (const answer of answers) assert.equal(answer.masks.subject, "ada");

  const { client_id } = await fileCredentials(path).read(new Request(APP));
  const logout = await fake.logoutToken({ aud: client_id, sub: "ada" });
  const posted = await browser.fetch("/api/auth/masks/logout/backchannel", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ logout_token: logout }),
  });

  assert.equal(posted.status, 200);
  assert.equal(await session(other), null);
});

test("signing in again revokes the refresh token the session held before", async () => {
  const held = await signedIn();
  const { fake, browser } = held;
  const started = await browser.fetch(
    "/api/auth/masks/signin?privilege=admin&callbackUrl=/admin",
  );

  await throughMasks(held, started);
  await new Promise((resolve) => setTimeout(resolve, 50));

  assert.equal(fake.revoked.length, 1);
});

test("an unconnected app cannot finish a sign-in through its stand-in provider", async () => {
  const held = await setup();
  const config = await held.auth.masks.config(new Request(APP));
  const [provider] = config.providers;

  assert.equal(provider.type, "oauth");
  assert.equal(provider.authorization.url, `${APP}/api/auth/masks/handshake`);
  assert.equal(new URL(provider.token).hostname, "masks.invalid");
  assert.equal(new URL(provider.userinfo).hostname, "masks.invalid");

  const account = { provider: "masks", type: "oauth", access_token: "a" };

  assert.equal(await config.callbacks.signIn({ account }), false);
  assert.equal(
    await config.callbacks.jwt({ token: {}, account, profile: { sub: "x" } }),
    null,
  );
});

test("servers that share a refresh store refresh a sign-in once between them", async () => {
  const { memoryRefreshes } = await import("../dist/index.js");
  const refreshes = memoryRefreshes();
  const held = await signedIn({
    masks: { refreshes },
    before: (fake) => {
      fake.lifetime = 1;
    },
  });
  const { fake, browser, credentials } = held;
  const other = masksAuth(NextAuth, {
    issuer: fake.url,
    resource: APP,
    secret: SECRET,
    trustHost: true,
    credentials,
    refreshes,
  });
  const second = new Browser((request) => other.handlers.GET(request), APP);
  const forget = () =>
    globalThis[Symbol.for("@masks/server v1 authjs refreshes")].clear();

  second.jar = browser.jar;
  fake.lifetime = 3600;

  const before = fake.tokenRequests.length;
  const first = session(browser);

  await new Promise((resolve) => setTimeout(resolve, 5));
  forget();

  const answers = [await first, await session(second)];

  forget();
  answers.push(await session(second));

  const refreshed = fake.tokenRequests
    .slice(before)
    .filter((grant) => grant === "refresh_token");

  assert.equal(refreshed.length, 1);
  for (const answer of answers) assert.equal(answer.masks.subject, "ada");
});

test("a refusal one server saw signs the person out on every server", async () => {
  const { memoryRefreshes } = await import("../dist/index.js");
  const refreshes = memoryRefreshes();
  const held = await signedIn({
    masks: { refreshes },
    before: (fake) => {
      fake.lifetime = 1;
    },
  });
  const { fake, browser } = held;

  const elsewhere = new Browser(browser.handler, APP);

  elsewhere.jar = new Map(browser.jar);
  fake.refreshRefusal = { status: 400, code: "invalid_grant" };

  assert.equal(await session(browser), null);

  globalThis[Symbol.for("@masks/server v1 authjs refreshes")].clear();
  fake.refreshRefusal = undefined;

  assert.equal(await session(elsewhere), null);
  assert.equal(
    fake.tokenRequests.filter((grant) => grant === "refresh_token").length,
    1,
  );
});

test("signing out ends the session here, and everywhere signs out of masks and comes back", async () => {
  const held = await signedIn();
  const { fake, browser, credentials } = held;
  const { client_id } = await credentials.read(new Request(APP));

  assert.equal(
    fake.handshakes[0].get("post_logout_redirect_uri"),
    `${APP}/api/auth/masks/logout/return`,
  );

  const forged = await browser.fetch("/api/auth/masks/logout", {
    method: "POST",
    headers: { "sec-fetch-site": "cross-site" },
  });

  assert.equal(forged.status, 403);
  assert.ok((await session(browser)).masks);

  const left = await browser.fetch(
    "/api/auth/masks/logout?everywhere&callbackUrl=/goodbye",
  );
  const target = new URL(left.headers.get("location"));

  assert.equal(left.status, 303);
  assert.equal(target.origin, fake.url);
  assert.equal(target.searchParams.get("client_id"), client_id);
  assert.equal(
    target.searchParams.get("post_logout_redirect_uri"),
    `${APP}/api/auth/masks/logout/return`,
  );
  assert.equal(await session(browser), null);
  assert.equal(fake.revoked.length, 1);

  const stale = await browser.fetch(
    "/api/auth/masks/logout/return?state=forged",
  );

  assert.equal(stale.status, 400);

  const again = await browser.fetch(
    "/api/auth/masks/logout?everywhere&callbackUrl=/goodbye",
  );
  const state = new URL(again.headers.get("location")).searchParams.get(
    "state",
  );
  const back = await browser.fetch(
    `/api/auth/masks/logout/return?state=${state}`,
  );

  assert.equal(back.status, 303);
  assert.equal(back.headers.get("location"), "/goodbye");
});

test("signing out without everywhere stays in the app", async () => {
  const held = await signedIn();
  const left = await held.browser.fetch("/api/auth/masks/logout", {
    method: "POST",
    body: new URLSearchParams({ callbackUrl: "/bye" }),
    headers: { "content-type": "application/x-www-form-urlencoded" },
  });

  assert.equal(left.status, 303);
  assert.equal(left.headers.get("location"), "/bye");
  assert.equal(await session(held.browser), null);
});

test("the avatar comes through the app with the person's token", async () => {
  const held = await signedIn();
  const { fake, browser } = held;
  const found = await session(browser);

  assert.equal(found.user.image, "/api/auth/masks/avatar");
  assert.equal(found.masks.avatar_url, "/api/auth/masks/avatar");

  const photo = await browser.fetch("/api/auth/masks/avatar?size=100");
  assert.equal(photo.status, 200);
  assert.equal(photo.headers.get("content-type"), "image/png");
  assert.equal(await photo.text(), "png-bytes");
  assert.match(fake.avatarAsks.at(-1), /size=128/);

  fake.avatarRedirect = "http://elsewhere.example/a.png";
  assert.equal((await browser.fetch("/api/auth/masks/avatar")).status, 404);

  const stranger = new Browser(browser.handler, APP);
  assert.equal((await stranger.fetch("/api/auth/masks/avatar")).status, 404);
});

test("a provider connection is finished only by the person who started it", async () => {
  const held = await signedIn({
    masks: { delegations: "/connect/callback" },
  });
  const { fake, browser, auth } = held;
  const asked = fake.handshakes[0];

  assert.deepEqual(asked.getAll("redirect_uris"), [
    `${APP}/api/auth/callback/masks`,
    `${APP}/connect/callback`,
  ]);
  assert.match(asked.get("scope"), /(^| )masks:delegate:( |$)/);

  const started = await auth.masks.startDelegation(
    browser.request("/connect"),
    "google",
  );
  browser.keep(started);
  const back = new URL(fake.authorize(started.headers.get("location")));
  const { connection, cookies } = await auth.masks.finishDelegation(
    browser.request(`${back.pathname}${back.search}`),
  );

  assert.equal(back.pathname, "/connect/callback");
  assert.equal(connection.connection, "connection-google");
  assert.equal(connection.account, "ada");
  assert.match(cookies[0], /^masks-delegation=;/);

  const again = await auth.masks.startDelegation(
    browser.request("/connect"),
    "google",
  );
  browser.keep(again);
  const someoneElse = new URL(
    fake.authorize(again.headers.get("location"), { sub: "eve" }),
  );
  await assert.rejects(
    auth.masks.finishDelegation(
      browser.request(`${someoneElse.pathname}${someoneElse.search}`),
    ),
    (error) => error.code === "access_denied",
  );

  const stranger = new Browser(browser.handler, APP);
  await assert.rejects(
    auth.masks.finishDelegation(
      stranger.request(`${back.pathname}${back.search}`),
    ),
    (error) => error.code === "invalid_state",
  );

  const signedOut = await auth.masks.startDelegation(
    stranger.request("/connect"),
    "google",
  );
  assert.equal(signedOut.status, 303);
  assert.equal(
    signedOut.headers.get("location"),
    "/api/auth/masks/signin?callbackUrl=%2Fconnect",
  );
});

test("the Auth.js names for the issuer and client are read from the environment", () => {
  const before = { ...process.env };

  try {
    process.env.AUTH_MASKS_ISSUER = "https://masks.test";
    process.env.AUTH_MASKS_ID = "from-auth-env";
    const auth = masksAuth(NextAuth, { secret: SECRET, trustHost: true });

    assert.equal(auth.masks.issuerURL, "https://masks.test");
  } finally {
    for (const name of ["AUTH_MASKS_ISSUER", "AUTH_MASKS_ID"]) {
      if (before[name] === undefined) delete process.env[name];
      else process.env[name] = before[name];
    }
  }
});

test("the proxy keeps the answer the authorized callback gives", async () => {
  const held = await setup({
    masks: {
      callbacks: {
        authorized: ({ auth, request }) =>
          auth || !new URL(request.url).pathname.startsWith("/dashboard"),
      },
    },
  });

  const open = await held.auth.proxy(new NextRequest(`${APP}/about`));
  assert.equal(open.headers.get("x-middleware-next"), "1");

  const refused = await held.auth.proxy(new NextRequest(`${APP}/dashboard`));
  assert.equal(refused.headers.get("x-middleware-next"), null);
  assert.match(refused.headers.get("location") ?? "", /signin/);
});
