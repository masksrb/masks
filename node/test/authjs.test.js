import assert from "node:assert/strict";
import { after, test } from "node:test";
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

  const forged = await browser.fetch("/api/auth/masks/handshake/disconnect", {
    method: "POST",
    headers: { "sec-fetch-site": "cross-site" },
  });
  assert.equal(forged.status, 403);
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
