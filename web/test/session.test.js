import assert from "node:assert/strict";
import { test } from "node:test";
import { createSession } from "../dist/session.js";

const ACCOUNT = {
  signed_in: true,
  subject: "actor-1",
  name: "Ada",
  email: "user@example.invalid",
  tenant: { uuid: "t-1", subdomain: "demo", name: "Demo" },
  scopes: ["openid", "uris:read", "admin"],
};

function server(responses) {
  const calls = [];
  let index = 0;

  const fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    const next = responses[Math.min(index++, responses.length - 1)];

    return new Response(
      next.body === undefined ? null : JSON.stringify(next.body),
      {
        status: next.status,
        headers: { "content-type": "application/json" },
      },
    );
  };

  return { fetch, calls };
}

function client(responses, options = {}) {
  const upstream = server(responses);

  return {
    upstream,
    subject: createSession({
      fetch: upstream.fetch,
      csrfToken: () => "csrf-1",
      ...options,
    }),
  };
}

test("a signed-in session comes back as an account", async () => {
  const { subject, upstream } = client([{ status: 200, body: ACCOUNT }]);

  const account = await subject.session();

  assert.equal(account.subject, "actor-1");
  assert.equal(account.tenant.subdomain, "demo");
  assert.deepEqual(account.scopes, ["openid", "uris:read", "admin"]);
  assert.equal(upstream.calls[0].url, "/auth/session");
  assert.equal(upstream.calls[0].init.credentials, "same-origin");
});

test("a 401 is null rather than a throw, because signed-out is not an error", async () => {
  const { subject } = client([
    { status: 401, body: { signed_in: false, login_url: "/auth" } },
  ]);

  assert.equal(await subject.session(), null);
});

test("any other failure does throw", async () => {
  const { subject } = client([{ status: 500, body: {} }]);

  await assert.rejects(
    () => subject.session(),
    (error) => error.code === "session_failed" && error.status === 500,
  );
});

test("the login url carries where to come back to", () => {
  const { subject } = client([{ status: 200, body: ACCOUNT }]);

  assert.equal(
    subject.loginUrl({ returnTo: "/uris/7?tab=analysis" }),
    "/auth?return_to=%2Furis%2F7%3Ftab%3Danalysis",
  );
});

test("a custom base path is honoured", async () => {
  const { subject, upstream } = client([{ status: 200, body: ACCOUNT }], {
    basePath: "/session-api/",
  });

  await subject.session();

  assert.equal(upstream.calls[0].url, "/session-api/session");
  assert.equal(
    subject.loginUrl({ returnTo: "/" }),
    "/session-api?return_to=%2F",
  );
});

test("logout sends the csrf token and no bearer", async () => {
  const { subject, upstream } = client([
    { status: 200, body: { signed_in: false } },
  ]);

  await subject.logout();

  const { init } = upstream.calls[0];
  assert.equal(init.method, "DELETE");
  assert.equal(init.headers["X-CSRF-Token"], "csrf-1");
  assert.equal(init.credentials, "same-origin");
  assert.equal(init.headers.Authorization, undefined);
});

test("logout without a csrf token omits the header rather than sending null", async () => {
  const { subject, upstream } = client([{ status: 200, body: {} }], {
    csrfToken: () => null,
  });

  await subject.logout();

  assert.ok(!("X-CSRF-Token" in upstream.calls[0].init.headers));
});

test("no token is ever held by the session client", async () => {
  const { subject } = client([{ status: 200, body: ACCOUNT }]);
  const account = await subject.session();

  assert.equal(account.access_token, undefined);
  assert.ok(!Object.keys(subject).includes("accessToken"));
});

test("an app that has not shaken hands says so, rather than offering a login", async () => {
  const { subject } = client([
    {
      status: 401,
      body: {
        signed_in: false,
        error: "handshake_required",
        handshake_url: "/auth/handshake",
      },
    },
  ]);

  const status = await subject.status();

  assert.equal(status.state, "handshake_required");
  assert.equal(status.handshakeUrl, "/auth/handshake");
  assert.equal(await subject.session(), null);
});

test("a signed-out session names where to sign in", async () => {
  const { subject } = client([
    {
      status: 401,
      body: { signed_in: false, error: "login_required", login_url: "/auth" },
    },
  ]);

  const status = await subject.status();

  assert.equal(status.state, "signed_out");
  assert.equal(status.loginUrl, "/auth");
});

test("a refusal with no url falls back to the paths this client knows", async () => {
  const { subject } = client([
    { status: 401, body: { signed_in: false, error: "handshake_required" } },
  ]);

  assert.equal((await subject.status()).handshakeUrl, "/auth/handshake");
});

test("a signed-in status carries the account itself", async () => {
  const { subject } = client([{ status: 200, body: ACCOUNT }]);
  const status = await subject.status();

  assert.equal(status.state, "signed_in");
  assert.equal(status.account.subject, "actor-1");
});

test("signing out everywhere asks the bff for it and follows where it says", async () => {
  const assigned = [];
  const held = globalThis.window;
  globalThis.window = { location: { assign: (url) => assigned.push(url) } };

  const { subject, upstream } = client([
    {
      status: 200,
      body: {
        signed_in: false,
        logout_url: "https://demo.auth.test/logout?client_id=app",
      },
    },
  ]);

  const pending = subject.logout({ everywhere: true });
  await Promise.race([pending, new Promise((done) => setTimeout(done, 10))]);

  assert.ok(upstream.calls[0].url.endsWith("/logout?everywhere=1"));
  assert.deepEqual(assigned, ["https://demo.auth.test/logout?client_id=app"]);

  globalThis.window = held;
});

test("an ordinary sign out does not leave the app", async () => {
  const assigned = [];
  const held = globalThis.window;
  globalThis.window = { location: { assign: (url) => assigned.push(url) } };

  const { subject, upstream } = client([
    {
      status: 200,
      body: { signed_in: false, logout_url: "https://elsewhere" },
    },
  ]);

  await subject.logout();

  assert.ok(upstream.calls[0].url.endsWith("/logout"));
  assert.deepEqual(assigned, []);

  globalThis.window = held;
});
