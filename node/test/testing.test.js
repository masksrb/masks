import assert from "node:assert/strict";
import { after, test } from "node:test";
import { Client, Issuer } from "../dist/index.js";
import { Fake } from "../dist/testing.js";

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

  return { fake, client };
}

const redirectURI = "http://app.localhost:3000/auth/callback";

test("a sign-in completes against the fake", async () => {
  const { fake, client } = await app();

  const started = await client.start({
    redirectURI,
    scope: ["openid", "profile"],
  });
  const signedIn = await client.complete(fake.authorize(started.url), started);

  assert.equal(signedIn.claims.sub, "ada");
  assert.equal(signedIn.claims.name, "Ada Lovelace");
  assert.ok(signedIn.token.access_token);
  assert.ok(signedIn.token.refresh_token);
});

test("a refresh against the fake returns a new token for the same person", async () => {
  const { fake, client } = await app();

  const started = await client.start({ redirectURI, scope: ["openid"] });
  const signedIn = await client.complete(fake.authorize(started.url), started);
  const refreshed = await client.refresh(signedIn.token.refresh_token);

  assert.notEqual(refreshed.access_token, signedIn.token.access_token);
  assert.notEqual(refreshed.refresh_token, signedIn.token.refresh_token);
  assert.deepEqual(
    fake.tokenRequests.filter((grant) => grant === "refresh_token"),
    ["refresh_token"],
  );
});

test("a logout token the fake mints verifies for the client it names", async () => {
  const { fake, client } = await app();

  const logout = await client.logoutToken(
    await fake.logoutToken({ aud: "app", sub: "ada", sid: "sid-1" }),
  );

  assert.equal(logout.sub, "ada");
  assert.equal(logout.sid, "sid-1");
});
