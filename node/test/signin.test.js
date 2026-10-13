import assert from "node:assert/strict";
import { after, test } from "node:test";
import {
  Client,
  DelegationRefused,
  Delegations,
  DelegationUnavailable,
  ForbiddenError,
  Handshake,
  hasCode,
  InvalidTokenError,
  Issuer,
  member,
  organizationKey,
  organizationOf,
  organizationsOf,
  pictureOf,
} from "../dist/index.js";
import { Fake } from "./fake.js";

const closers = [];

after(async () => {
  for (const close of closers) await close();
});

async function app() {
  const fake = await Fake.start();
  closers.push(fake.close);
  fake.add("app", { secret: "s3cret", method: "client_secret_basic" });

  const issuer = await Issuer.discover(fake.url);
  const client = new Client({ issuer, id: "app", secret: "s3cret" });

  return { fake, issuer, client };
}

const redirectURI = "http://app.localhost:3000/auth/callback";

test("a sign-in goes through masks with PKCE, a nonce, and an organization", async () => {
  const { fake, client } = await app();

  const started = await client.start({
    redirectURI,
    scope: ["openid", "profile", "organization"],
    resource: ["http://app.localhost:3000"],
    organization: " Acme ",
    prompt: "login",
    maxAge: 600,
  });
  const asked = new URL(started.url).searchParams;

  assert.equal(new URL(started.url).pathname, "/authorize");
  assert.equal(asked.get("response_type"), "code");
  assert.equal(asked.get("client_id"), "app");
  assert.equal(asked.get("code_challenge_method"), "S256");
  assert.equal(asked.get("organization"), "acme");
  assert.equal(asked.get("prompt"), "login");
  assert.equal(asked.get("max_age"), "600");
  assert.equal(asked.get("nonce"), started.nonce);
  assert.ok(started.verifier.length >= 43);
  assert.notEqual(asked.get("code_challenge"), started.verifier);

  const { token, claims } = await client.complete(
    fake.authorize(started.url),
    started,
  );

  assert.equal(claims.sub, "ada");
  assert.equal(claims.nonce, started.nonce);
  assert.ok(token.refresh_token);
  assert.ok(token.expires_at > Date.now() / 1000);
});

test("a sign-in without openid sends no nonce", async () => {
  const { client } = await app();
  const started = await client.start({ redirectURI, scope: ["files:read"] });

  assert.equal(started.nonce, undefined);
  assert.equal(new URL(started.url).searchParams.get("nonce"), null);
  assert.equal(
    (await client.start({ redirectURI, organization: "-nope" })).url.includes(
      "organization",
    ),
    false,
  );
});

test("a sign-in refuses what did not come back from this request", async () => {
  const { fake, client } = await app();
  const cases = {
    "an error": [{ error: "access_denied" }, "access_denied"],
    "another state": [{ state: "forged" }, "invalid_state"],
    "another issuer": [{ iss: "https://elsewhere.example" }, "invalid_issuer"],
  };

  for (const [name, [options, code]] of Object.entries(cases)) {
    const started = await client.start({ redirectURI });

    await assert.rejects(
      client.complete(fake.authorize(started.url, options), started),
      (error) => hasCode(error, code),
      name,
    );
  }

  const started = await client.start({ redirectURI });
  const back = new URL(fake.authorize(started.url));
  back.searchParams.delete("iss");

  await assert.rejects(client.complete(back, started), (error) =>
    hasCode(error, "invalid_issuer"),
  );

  fake.nonceOverride = "replayed";
  const again = await client.start({ redirectURI });

  await assert.rejects(
    client.complete(fake.authorize(again.url), again),
    (error) => hasCode(error, "invalid_nonce"),
  );
});

test("a code is redeemed only with its verifier and redirect URI", async () => {
  const { fake, client } = await app();
  const started = await client.start({ redirectURI });
  const back = fake.authorize(started.url);

  await assert.rejects(
    client.complete(back, { ...started, verifier: "x".repeat(43) }),
    (error) => hasCode(error, "invalid_grant"),
  );
});

test("an id token for another client is refused", async () => {
  const { fake, client } = await app();
  const now = Math.floor(Date.now() / 1000);
  const good = { iss: fake.url, sub: "ada", aud: "app", exp: now + 60 };

  assert.equal(
    (await client.identity(await fake.issue(good, "JWT"))).sub,
    "ada",
  );

  for (const [name, claims, typ] of [
    ["another audience", { ...good, aud: "other" }, "JWT"],
    ["several audiences", { ...good, aud: ["app", "other"] }, "JWT"],
    ["an access token", good, "at+jwt"],
    ["expired", { ...good, exp: now - 600 }, "JWT"],
  ]) {
    await assert.rejects(
      client.identity(await fake.issue(claims, typ)),
      InvalidTokenError,
      name,
    );
  }
});

test("userinfo answers for the token's subject", async () => {
  const { fake, client } = await app();
  const started = await client.start({ redirectURI });
  const { token } = await client.complete(fake.authorize(started.url), started);

  const found = await client.userinfo(token);

  assert.equal(found.sub, "ada");
  assert.equal(found.email, "ada@example.com");
  await assert.rejects(client.userinfo("nonsense"), MasksErrorWithStatus(401));
});

function MasksErrorWithStatus(status) {
  return (error) => error.status === status;
}

test("the end session URL names the client and where to come back", async () => {
  const { fake, client } = await app();
  const url = new URL(
    client.endSessionURL({
      postLogoutRedirectURI:
        "http://app.localhost:3000/auth/handshake/callback",
      state: "s",
    }),
  );

  assert.equal(url.origin + url.pathname, `${fake.url}/logout`);
  assert.equal(url.searchParams.get("client_id"), "app");
  assert.equal(url.searchParams.get("state"), "s");
  assert.equal(
    url.searchParams.get("post_logout_redirect_uri"),
    "http://app.localhost:3000/auth/handshake/callback",
  );
});

test("a logout token is checked before it ends anything", async () => {
  const { fake, client } = await app();

  const good = await client.logoutToken(
    await fake.logoutToken({ aud: "app", sub: "ada", sid: "s-1" }),
  );
  assert.equal(good.sid, "s-1");

  const cases = {
    "an id token": await fake.logoutToken({ aud: "app", sub: "ada" }, "JWT"),
    "a nonce": await fake.logoutToken({ aud: "app", sub: "ada", nonce: "n" }),
    "no subject or session": await fake.logoutToken({ aud: "app" }),
    "another audience": await fake.logoutToken({ aud: "other", sub: "ada" }),
    "no event": await fake.logoutToken({ aud: "app", sub: "ada", events: {} }),
    "no expiry": await fake.logoutToken({
      aud: "app",
      sub: "ada",
      exp: undefined,
    }),
    "an expiry passed": await fake.logoutToken({
      aud: "app",
      sub: "ada",
      exp: Math.floor(Date.now() / 1000) - 600,
    }),
  };

  for (const [name, token] of Object.entries(cases)) {
    await assert.rejects(client.logoutToken(token), InvalidTokenError, name);
  }
});

test("a handshake asks masks to register this app and redeems the answer", async () => {
  const { fake, issuer } = await app();
  const handshake = new Handshake(issuer, {
    name: "Catalog",
    resource: "http://app.localhost:3000",
    redirectURIs: [redirectURI],
    returnTo: "http://app.localhost:3000/auth/handshake/callback",
    scope: ["openid", "profile email", "catalog:read"],
    backchannelLogoutURI: "http://app.localhost:3000/auth/logout/backchannel",
    postLogoutRedirectUri: "http://app.localhost:3000/auth/logout/return",
  });

  const started = handshake.start();
  const asked = new URL(started.url).searchParams;

  assert.equal(new URL(started.url).pathname, "/handshake");
  assert.equal(asked.get("client_name"), "Catalog");
  assert.equal(asked.get("resource"), "http://app.localhost:3000");
  assert.equal(asked.get("scope"), "openid profile email catalog:read");
  assert.deepEqual(asked.getAll("redirect_uris"), [redirectURI]);
  assert.equal(
    asked.get("backchannel_logout_uri"),
    "http://app.localhost:3000/auth/logout/backchannel",
  );
  assert.equal(asked.get("state"), started.state);
  assert.equal(
    asked.get("post_logout_redirect_uri"),
    "http://app.localhost:3000/auth/logout/return",
  );

  const registration = await handshake.complete(
    new URL(fake.shake(started.url)),
    started.state,
  );

  assert.ok(registration.client_id);
  assert.ok(registration.client_secret);
  assert.ok(registration.registration_access_token);
  assert.equal(
    fake.clients.get(registration.client_id).metadata
      .token_endpoint_auth_method,
    "client_secret_basic",
  );
  assert.deepEqual(
    fake.clients.get(registration.client_id).metadata.grant_types,
    ["authorization_code", "refresh_token"],
  );
});

test("a handshake refuses another browser, another issuer, and a refusal", async () => {
  const { fake, issuer } = await app();
  const handshake = new Handshake(issuer, {
    name: "Catalog",
    resource: "http://app.localhost:3000",
    redirectURIs: [redirectURI],
    returnTo: "http://app.localhost:3000/auth/handshake/callback",
  });

  for (const [options, code] of [
    [{ state: "forged" }, "invalid_state"],
    [{ iss: "https://elsewhere.example" }, "invalid_issuer"],
    [{ error: "access_denied" }, "access_denied"],
  ]) {
    const started = handshake.start();

    await assert.rejects(
      handshake.complete(
        new URL(fake.shake(started.url, options)),
        started.state,
      ),
      (error) => hasCode(error, code),
    );
  }

  assert.throws(
    () =>
      new Handshake(issuer, {
        name: "Catalog",
        resource: "http://app.localhost:3000",
        redirectURIs: [redirectURI],
        returnTo: "http://app.localhost:3000/auth/handshake/callback",
        postLogoutRedirectUri: "https://elsewhere.example/bye",
      }),
    /shares the origin/,
  );

  fake.backchannel = false;
  const quiet = new Handshake(await Issuer.discover(fake.url), {
    name: "Catalog",
    resource: "http://app.localhost:3000",
    redirectURIs: [redirectURI],
    returnTo: "http://app.localhost:3000/auth/handshake/callback",
    backchannelLogoutURI: "http://app.localhost:3000/auth/logout/backchannel",
  });
  assert.equal(quiet.backchannelLogoutURI, undefined);
  assert.equal(
    new URL(quiet.start().url).searchParams.get("backchannel_logout_uri"),
    null,
  );

  assert.throws(
    () =>
      new Handshake(issuer, {
        name: "Catalog",
        resource: "http://app.localhost:3000",
        redirectURIs: ["https://elsewhere.example/callback"],
        returnTo: "http://app.localhost:3000/auth/handshake/callback",
      }),
    /shares the origin/,
  );
});

test("a delegation connects a provider and releases its token", async () => {
  const { fake, client } = await app();
  const delegations = new Delegations(
    client,
    "http://app.localhost:3000/connect/callback",
  );

  const started = await delegations.start({ provider: "google" });
  assert.equal(
    new URL(started.url).searchParams.get("scope"),
    "openid offline_access masks:delegate:google",
  );

  const held = await delegations.finish(
    new URL(fake.authorize(started.url)),
    started,
  );

  assert.equal(held.connection, "connection-google");
  assert.equal(held.provider_name, "Google");
  assert.ok(held.secret);

  const upstream = await delegations.token(held.secret, held.connection);

  assert.equal(upstream.access_token, "from-the-provider");
  assert.notEqual(upstream.secret, held.secret);
  assert.equal(fake.exchanges.at(-1).audience, "connection-google");

  await assert.rejects(
    delegations.token(held.secret, held.connection),
    (error) =>
      error instanceof DelegationRefused && error.code === "invalid_grant",
  );

  fake.refreshRefusal = { status: 503, code: "temporarily_unavailable" };
  await assert.rejects(
    delegations.token(upstream.secret, held.connection),
    (error) =>
      error instanceof DelegationUnavailable && error.secret === undefined,
  );
});

test("a declined delegation is refused and says whether to sign in again", async () => {
  const { fake, client } = await app();
  const delegations = new Delegations(client, redirectURI);
  const started = await delegations.start({ provider: "google" });

  await assert.rejects(
    delegations.finish(
      new URL(fake.authorize(started.url, { error: "login_required" })),
      started,
    ),
    (error) => error instanceof DelegationRefused && error.signedInAgain,
  );
  await assert.rejects(delegations.start({ provider: "../x" }), /by key/);
});

test("organizations and roles are read from claims", () => {
  const claims = {
    picture: undefined,
    "masks:avatars": { identicon: "https://id.example/i" },
    org: { id: "o-1", key: "acme", name: "Acme", role: "billing" },
    orgs: [
      { id: "o-1", key: "acme", role: "billing" },
      { id: "o-2", key: "globex" },
      "junk",
    ],
  };

  assert.deepEqual(organizationOf(claims), {
    id: "o-1",
    key: "acme",
    name: "Acme",
    role: "billing",
  });
  assert.equal(organizationsOf(claims).length, 1);
  assert.equal(pictureOf(claims), "https://id.example/i");
  assert.equal(member(claims, ["owner", "billing"]).key, "acme");
  assert.equal(member(claims, [], "o-1").key, "acme");
  assert.equal(organizationKey("ACME "), "acme");
  assert.equal(organizationKey("a b"), undefined);

  assert.throws(
    () => member(claims, ["owner"]),
    (error) =>
      error instanceof ForbiddenError && error.code === "insufficient_role",
  );
  assert.throws(
    () => member(claims, [], "globex"),
    (error) => error.code === "insufficient_organization",
  );
  assert.throws(
    () => member({}, []),
    (error) =>
      error.code === "insufficient_organization" &&
      error.scope === "organization",
  );
});
