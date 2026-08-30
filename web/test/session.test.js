import assert from "node:assert/strict";
import { test } from "node:test";
import { createSession } from "../dist/session.js";

const ACCOUNT = {
  signed_in: true,
  subject: "actor-1",
  name: "Jon",
  email: "jon@example.invalid",
  tenant: { uuid: "t-1", subdomain: "jons", name: "Jons" },
  scopes: ["openid", "things:read", "admin"],
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
  assert.equal(account.tenant.subdomain, "jons");
  assert.deepEqual(account.scopes, ["openid", "things:read", "admin"]);
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
    subject.loginUrl({ returnTo: "/things/7?tab=analysis" }),
    "/auth?return_to=%2Fthings%2F7%3Ftab%3Danalysis",
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
