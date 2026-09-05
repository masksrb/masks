import assert from "node:assert/strict";
import { createSign, generateKeyPairSync } from "node:crypto";
import { test } from "node:test";
import { createBrowserClient } from "../dist/browser.js";
import { createSession } from "../dist/session.js";

const ISSUER = "https://demo.auth.test";
const KID = "test-key";
const KEY = generateKeyPairSync("rsa", { modulusLength: 2048 });

const AVATARS = {
  photo: `${ISSUER}/avatars/actor-1/photo/aaaaaaaaaaaaaaaa`,
  identicon: `${ISSUER}/avatars/actor-1/identicon/bbbbbbbbbbbbbbbb`,
  initials: `${ISSUER}/avatars/actor-1/initials/cccccccccccccccc`,
};

const ACCOUNT = {
  signed_in: true,
  subject: "actor-1",
  name: "Ada Lovelace",
  picture: AVATARS.photo,
  avatars: AVATARS,
  scopes: ["openid", "profile"],
};

function b64(value) {
  return Buffer.from(value).toString("base64url");
}

function mint(claims = {}) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64(JSON.stringify({ alg: "RS256", typ: "JWT", kid: KID }));
  const payload = b64(
    JSON.stringify({
      iss: ISSUER,
      sub: "actor-1",
      aud: "app-1",
      iat: now,
      exp: now + 3600,
      ...claims,
    }),
  );

  const signature = createSign("RSA-SHA256")
    .update(`${header}.${payload}`)
    .sign(KEY.privateKey)
    .toString("base64url");

  return `${header}.${payload}.${signature}`;
}

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
    avatar_endpoint: `${ISSUER}/avatars`,
    avatar_styles_supported: ["photo", "identicon", "initials"],
    avatar_sizes_supported: [32, 64, 128, 256, 512],
    ...overrides,
  };
}

function browser({ document = discovery(), photo = null } = {}) {
  const calls = [];
  const store = memory();
  const held = { nonce: null };

  const json = (body, code = 200) =>
    new Response(JSON.stringify(body), {
      status: code,
      headers: { "content-type": "application/json" },
    });

  const fetch = async (url, init = {}) => {
    const target = String(url);
    calls.push({ url: target, init });

    if (target.includes("openid-configuration")) return json(document);

    if (target.includes("jwks")) {
      return json({
        keys: [
          {
            ...KEY.publicKey.export({ format: "jwk" }),
            kid: KID,
            use: "sig",
            alg: "RS256",
          },
        ],
      });
    }

    if (target.includes("/avatars/")) {
      if (photo === null) return new Response(null, { status: 404 });

      return new Response(photo, {
        status: 200,
        headers: { "content-type": "image/webp" },
      });
    }

    return json({
      access_token: "at-1",
      token_type: "Bearer",
      scope: "openid profile",
      expires_in: 3600,
      id_token: mint({ nonce: held.nonce, "masks:avatars": AVATARS }),
    });
  };

  const subject = createBrowserClient({
    issuer: ISSUER,
    clientId: "app-1",
    redirectUri: "https://app.test/callback",
    scope: "openid profile",
    fetch,
    storage: store,
  });

  return { subject, calls, store, held };
}

async function land({ subject, store, held }) {
  await subject.authorizeUrl({ returnTo: "/" });

  const waiting = JSON.parse(store.getItem("masks:pending"));
  held.nonce = waiting.nonce;

  return await subject.callback(
    `https://app.test/callback?code=c-1&state=${waiting.state}`,
  );
}

test("a session hands back every avatar the issuer released", async () => {
  const subject = createSession({
    fetch: async () =>
      new Response(JSON.stringify(ACCOUNT), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
  });

  const account = await subject.session();

  assert.deepEqual(account.avatars, AVATARS);
  assert.equal(account.picture, AVATARS.photo);
});

test("the photo goes through the backend, so the token stays there", () => {
  const subject = createSession({ basePath: "/auth" });

  assert.equal(subject.avatarUrl(ACCOUNT), "/auth/avatar");
  assert.equal(
    subject.avatarUrl(ACCOUNT, { style: "photo", size: 64 }),
    "/auth/avatar?size=64",
  );
});

test("a generated style is fetched straight from the issuer", () => {
  const subject = createSession();

  assert.equal(
    subject.avatarUrl(ACCOUNT, { style: "identicon" }),
    AVATARS.identicon,
  );
  assert.equal(
    subject.avatarUrl(ACCOUNT, { style: "initials", size: 32 }),
    `${AVATARS.initials}?size=32`,
  );
});

test("with no photo the default style falls back to the identicon", () => {
  const subject = createSession();
  const account = { ...ACCOUNT, avatars: { ...AVATARS, photo: null } };

  assert.equal(subject.avatarUrl(account), AVATARS.identicon);
  assert.equal(subject.avatarUrl(account, { style: "photo" }), null);
});

test("an account with no avatars at all is null, not a throw", () => {
  const subject = createSession();

  assert.equal(subject.avatarUrl(null), null);
  assert.equal(subject.avatarUrl({ signed_in: true, scopes: [] }), null);
});

test("the browser client builds an avatar url from discovery", async () => {
  const { subject } = browser();

  assert.equal(
    await subject.avatarUrl("actor-1"),
    `${ISSUER}/avatars/actor-1/identicon`,
  );
  assert.equal(
    await subject.avatarUrl("actor-1", { style: "initials", size: 128 }),
    `${ISSUER}/avatars/actor-1/initials?size=128`,
  );
});

test("a style the issuer does not advertise is refused before the request", async () => {
  const { subject } = browser({
    document: discovery({ avatar_styles_supported: ["identicon"] }),
  });

  await assert.rejects(() => subject.avatarUrl("actor-1", { style: "photo" }), {
    code: "invalid_style",
  });
});

test("an issuer with no avatar endpoint says so", async () => {
  const { subject } = browser({
    document: discovery({ avatar_endpoint: undefined }),
  });

  await assert.rejects(() => subject.avatarUrl("actor-1"), {
    code: "invalid_issuer",
  });
});

test("the id token carries the avatars, so no second request is needed", async () => {
  const session = browser();

  await land(session);

  assert.deepEqual(session.subject.avatars(), AVATARS);
});

test("the browser fetches a photo with the token attached", async () => {
  const session = browser({ photo: "webp-bytes" });

  await land(session);

  const blob = await session.subject.photo();
  const fetched = session.calls.find((call) => call.url.includes("/avatars/"));

  assert.equal(await blob.text(), "webp-bytes");
  assert.equal(fetched.url, `${ISSUER}/avatars/actor-1/photo`);
  assert.equal(fetched.init.headers.Authorization, "Bearer at-1");
});

test("no photo is null rather than a throw", async () => {
  const session = browser();

  await land(session);

  assert.equal(await session.subject.photo(), null);
});

test("a browser holding no token has no photo to fetch", async () => {
  const { subject } = browser({ photo: "webp-bytes" });

  assert.equal(await subject.photo("actor-1"), null);
});
