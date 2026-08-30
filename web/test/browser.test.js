import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import { createBrowserClient } from "../dist/browser.js";
import { challenge, encode, random } from "../dist/pkce.js";

const ISSUER = "https://jons.auth.test";

function memory() {
  const held = new Map();

  return {
    getItem: (key) => (held.has(key) ? held.get(key) : null),
    setItem: (key, value) => held.set(key, String(value)),
    removeItem: (key) => held.delete(key),
  };
}

function discovery(overrides = {}) {
  return {
    issuer: ISSUER,
    authorization_endpoint: `${ISSUER}/authorize`,
    token_endpoint: `${ISSUER}/token`,
    jwks_uri: `${ISSUER}/.well-known/jwks.json`,
    tenant: { uuid: "t-1", subdomain: "jons", name: "Jons" },
    ...overrides,
  };
}

function server({ document = discovery(), token = {}, status = 200 } = {}) {
  const calls = [];

  const fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });

    if (String(url).includes(".well-known")) {
      return new Response(JSON.stringify(document), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }

    return new Response(JSON.stringify(token), {
      status,
      headers: { "content-type": "application/json" },
    });
  };

  return { fetch, calls };
}

function client(options = {}) {
  const store = options.storage ?? memory();
  const upstream = options.server ?? server();

  return {
    store,
    upstream,
    subject: createBrowserClient({
      issuer: ISSUER,
      clientId: "app-1",
      redirectUri: "https://app.test/callback",
      scope: "openid profile things:read",
      resource: "https://app.test/mcp",
      fetch: upstream.fetch,
      storage: store,
      ...options.client,
    }),
  };
}

const GRANTED = {
  access_token: "at-1",
  id_token: "it-1",
  refresh_token: "rt-1",
  token_type: "Bearer",
  scope: "openid profile things:read",
  expires_in: 3600,
};

test("the challenge is a real S256 of the verifier", async () => {
  const verifier = random();
  const expected = encode(createHash("sha256").update(verifier).digest());

  assert.equal(await challenge(verifier), expected);
});

test("a verifier is url-safe and long enough to matter", () => {
  const verifier = random();

  assert.equal(verifier.length, 64);
  assert.match(verifier, /^[A-Za-z0-9\-._~]+$/);
});

test("the authorize url carries pkce, the resource, and a stored state", async () => {
  const { subject, store } = client();

  const url = new URL(await subject.authorizeUrl({ returnTo: "/catalog" }));
  const waiting = JSON.parse(store.getItem("masks:pending"));

  assert.equal(url.origin + url.pathname, `${ISSUER}/authorize`);
  assert.equal(url.searchParams.get("response_type"), "code");
  assert.equal(url.searchParams.get("client_id"), "app-1");
  assert.equal(url.searchParams.get("code_challenge_method"), "S256");
  assert.equal(url.searchParams.get("scope"), "openid profile things:read");
  assert.deepEqual(url.searchParams.getAll("resource"), [
    "https://app.test/mcp",
  ]);
  assert.equal(url.searchParams.get("state"), waiting.state);
  assert.equal(url.searchParams.get("nonce"), waiting.nonce);
  assert.equal(
    url.searchParams.get("code_challenge"),
    await challenge(waiting.verifier),
  );
  assert.equal(waiting.returnTo, "/catalog");
});

test("the verifier is never put in the authorize url", async () => {
  const { subject, store } = client();

  const url = await subject.authorizeUrl({ returnTo: "/" });
  const { verifier } = JSON.parse(store.getItem("masks:pending"));

  assert.ok(!url.includes(verifier));
});

test("a callback exchanges the code and returns where to go back to", async () => {
  const upstream = server({ token: GRANTED });
  const { subject, store } = client({ server: upstream });

  await subject.authorizeUrl({ returnTo: "/things/7" });
  const { state } = JSON.parse(store.getItem("masks:pending"));

  const { tokens, returnTo } = await subject.callback(
    `https://app.test/callback?code=abc&state=${state}`,
  );

  assert.equal(tokens.access_token, "at-1");
  assert.equal(returnTo, "/things/7");
  assert.equal(subject.accessToken(), "at-1");
  assert.equal(subject.authorization(), "Bearer at-1");
  assert.equal(subject.expired(), false);

  const posted = new URLSearchParams(upstream.calls.at(-1).init.body);
  assert.equal(posted.get("grant_type"), "authorization_code");
  assert.equal(posted.get("code"), "abc");
  assert.equal(posted.get("code_verifier").length, 64);
  assert.equal(posted.get("resource"), "https://app.test/mcp");
});

test("a mismatched state is refused", async () => {
  const { subject } = client({ server: server({ token: GRANTED }) });

  await subject.authorizeUrl({ returnTo: "/" });

  await assert.rejects(
    () => subject.callback("https://app.test/callback?code=abc&state=forged"),
    (error) => error.code === "invalid_state",
  );
});

test("a callback with nothing in flight is refused", async () => {
  const { subject } = client();

  await assert.rejects(
    () => subject.callback("https://app.test/callback?code=abc&state=any"),
    (error) => error.code === "invalid_state",
  );
});

test("the pending record is cleared even when the callback fails", async () => {
  const { subject, store } = client();

  await subject.authorizeUrl({ returnTo: "/" });
  await subject
    .callback("https://app.test/callback?code=a&state=forged")
    .catch(() => {});

  assert.equal(store.getItem("masks:pending"), null);
  assert.equal(subject.pending(), false);
});

test("an error on the callback is surfaced as the issuer named it", async () => {
  const { subject } = client();

  await subject.authorizeUrl({ returnTo: "/" });

  await assert.rejects(
    () =>
      subject.callback(
        "https://app.test/callback?error=access_denied&error_description=declined",
      ),
    (error) =>
      error.code === "access_denied" && error.description === "declined",
  );
});

test("a discovery document naming another issuer is refused", async () => {
  const { subject } = client({
    server: server({
      document: discovery({ issuer: "https://elsewhere.test" }),
    }),
  });

  await assert.rejects(
    () => subject.discover(),
    (error) => error.code === "invalid_issuer",
  );
});

test("discovery is fetched once and held", async () => {
  const upstream = server({ token: GRANTED });
  const { subject } = client({ server: upstream });

  await subject.discover();
  await subject.discover();
  await subject.authorizeUrl({ returnTo: "/" });

  const fetched = upstream.calls.filter((c) => c.url.includes(".well-known"));
  assert.equal(fetched.length, 1);
});

test("a token endpoint error becomes a MasksError", async () => {
  const { subject, store } = client({
    server: server({
      status: 400,
      token: { error: "invalid_grant", error_description: "that code expired" },
    }),
  });

  await subject.authorizeUrl({ returnTo: "/" });
  const { state } = JSON.parse(store.getItem("masks:pending"));

  await assert.rejects(
    () => subject.callback(`https://app.test/callback?code=a&state=${state}`),
    (error) =>
      error.code === "invalid_grant" &&
      error.description === "that code expired",
  );
});

test("refresh sends the refresh token and the resource", async () => {
  const upstream = server({ token: GRANTED });
  const { subject, store } = client({ server: upstream });

  await subject.authorizeUrl({ returnTo: "/" });
  const { state } = JSON.parse(store.getItem("masks:pending"));
  await subject.callback(`https://app.test/callback?code=a&state=${state}`);

  await subject.refresh();

  const posted = new URLSearchParams(upstream.calls.at(-1).init.body);
  assert.equal(posted.get("grant_type"), "refresh_token");
  assert.equal(posted.get("refresh_token"), "rt-1");
  assert.equal(posted.get("resource"), "https://app.test/mcp");
});

test("refresh without a token held is refused rather than sent", async () => {
  const upstream = server();
  const { subject } = client({ server: upstream });

  await assert.rejects(
    () => subject.refresh(),
    (error) => error.code === "invalid_grant",
  );
  assert.equal(upstream.calls.length, 0);
});

test("logout drops the token and anything in flight", async () => {
  const { subject, store } = client({ server: server({ token: GRANTED }) });

  await subject.authorizeUrl({ returnTo: "/" });
  const { state } = JSON.parse(store.getItem("masks:pending"));
  await subject.callback(`https://app.test/callback?code=a&state=${state}`);

  subject.logout();

  assert.equal(subject.accessToken(), null);
  assert.equal(subject.authorization(), null);
  assert.equal(subject.expired(), true);
  assert.equal(store.getItem("masks:pending"), null);
});

test("an expiring token reports expired inside the leeway", async () => {
  const { subject, store } = client({
    server: server({ token: { ...GRANTED, expires_in: 20 } }),
  });

  await subject.authorizeUrl({ returnTo: "/" });
  const { state } = JSON.parse(store.getItem("masks:pending"));
  await subject.callback(`https://app.test/callback?code=a&state=${state}`);

  assert.equal(subject.expired(30), true);
  assert.equal(subject.expired(0), false);
});
