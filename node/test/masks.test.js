import assert from "node:assert/strict";
import { after, test } from "node:test";
import { timing } from "../dist/client.js";
import {
  ACCESS_TOKEN_TYPE,
  Client,
  discoverResource,
  Foreign,
  GRANT_TOKEN_EXCHANGE,
  hasCode,
  hasScope,
  ID_TOKEN_TYPE,
  Insecure,
  InvalidToken,
  Issuer,
  Key,
  MasksError,
  MemoryReplayStore,
  proof,
  Unavailable,
  UPSTREAM_ACCESS_TOKEN_TYPE,
  Verifier,
  valid,
} from "../dist/index.js";
import { check } from "../dist/issuer.js";
import { Fake, json, listen } from "./fake.js";

const closers = [];

after(async () => {
  for (const close of closers) await close();
});

async function fake() {
  const held = await Fake.start();
  closers.push(held.close);

  return held;
}

async function signedClient(held) {
  const key = await Key.generate();
  const dpop = await Key.generate();

  held.add("signed", {
    method: "private_key_jwt",
    scope: "files:read",
    jwks: key.jwks(),
  });

  const issuer = await Issuer.discover(held.url);

  return {
    client: new Client({ issuer, id: "signed", key, dpop }),
    key,
    dpop,
    issuer,
  };
}

test("discovery refuses a document naming another issuer", async () => {
  const server = await listen((_, response) =>
    json(response, 200, { issuer: "https://elsewhere.example" }),
  );
  closers.push(server.close);

  await assert.rejects(Issuer.discover(server.url), /elsewhere/);
});

test("plain http is allowed only on this machine", () => {
  for (const allowed of [
    "https://id.example",
    "http://127.0.0.1:3000",
    "http://masks.localhost:12345",
    "http://[::1]:80",
  ]) {
    check(allowed);
  }

  for (const refused of [
    "http://id.example",
    "http://10.0.0.4",
    "ftp://id.example",
    "id.example",
  ]) {
    assert.throws(() => check(refused), undefined, refused);
  }

  assert.throws(() => check("http://10.0.0.4"), Insecure);
  check("http://10.0.0.4", { allowPlainHTTP: true });
});

for (const method of ["client_secret_basic", "client_secret_post"]) {
  test(`client credentials with ${method}`, async () => {
    const held = await fake();
    held.add("machine", { secret: "s3cr:et/+ &", method, scope: "files:read" });

    const client = new Client({
      issuer: await Issuer.discover(held.url),
      id: "machine",
      secret: "s3cr:et/+ &",
      method,
    });
    const token = await client.clientCredentials();

    assert.equal(token.token_type, "Bearer");
    assert.equal(token.scope, "files:read");
    assert.ok(valid(token));
  });
}

test("a wrong secret is an invalid client", async () => {
  const held = await fake();
  held.add("machine", { secret: "right", method: "client_secret_basic" });

  const client = new Client({
    issuer: await Issuer.discover(held.url),
    id: "machine",
    secret: "wrong",
  });

  await assert.rejects(client.clientCredentials(), (error) => {
    assert.ok(error instanceof MasksError);
    assert.equal(error.code, "invalid_client");
    assert.equal(error.status, 401);
    return true;
  });
});

test("a private_key_jwt client gets a token held to its key", async () => {
  const held = await fake();
  const { client, dpop, issuer } = await signedClient(held);

  const token = await client.clientCredentials({
    scope: ["files:read"],
    resource: [held.audience],
  });
  assert.equal(token.token_type, "DPoP");

  const claims = await new Verifier(issuer, held.audience).verify(
    token.access_token,
  );
  assert.equal(claims.cnf.jkt, dpop.thumbprint);
});

test("each assertion is used once", async () => {
  const held = await fake();
  const { client } = await signedClient(held);

  for (let index = 0; index < 3; index++) await client.clientCredentials();
});

test("a token endpoint nonce is answered once and remembered", async () => {
  const held = await fake();
  held.nonce = "fresh-nonce";
  const { client } = await signedClient(held);

  await client.clientCredentials();

  held.refusals = 0;
  await client.clientCredentials();
  assert.equal(held.refusals, 0);
});

test("a Bearer answer to a DPoP client is refused", async () => {
  let base = "";
  const server = await listen((request, response) => {
    if (request.url === "/.well-known/openid-configuration") {
      return json(response, 200, {
        issuer: base,
        token_endpoint: `${base}/token`,
      });
    }

    json(response, 200, {
      access_token: "plain",
      token_type: "Bearer",
      expires_in: 60,
    });
  });
  base = server.url;
  closers.push(server.close);

  const client = new Client({
    issuer: await Issuer.discover(server.url),
    id: "machine",
    secret: "secret",
    dpop: await Key.generate(),
  });

  await assert.rejects(client.clientCredentials(), (error) =>
    hasCode(error, "invalid_dpop_proof"),
  );
});

test("the device flow waits for approval", async () => {
  timing.devicePause = 10;

  const held = await fake();
  held.pending = 3;
  held.add("tv", { method: "none", scope: "openid" });

  const client = new Client({
    issuer: await Issuer.discover(held.url),
    id: "tv",
  });
  const device = await client.deviceAuthorization({ scope: ["openid"] });

  assert.equal(device.user_code, "ABCD EFGH");

  const token = await client.awaitDevice(device);

  assert.ok(token.access_token);
  assert.equal(held.pending, 0);
});

test("the device flow stops with its signal", async () => {
  timing.devicePause = 10;

  const held = await fake();
  held.pending = 1000;
  held.add("tv", { method: "none" });

  const client = new Client({
    issuer: await Issuer.discover(held.url),
    id: "tv",
  });
  const device = await client.deviceAuthorization();

  await assert.rejects(
    client.awaitDevice(device, { signal: AbortSignal.timeout(100) }),
    (error) => error.name === "TimeoutError",
  );
});

test("a refresh source keeps each rotated token", async () => {
  const held = await fake();
  held.add("app", { secret: "secret", method: "client_secret_basic" });

  const client = new Client({
    issuer: await Issuer.discover(held.url),
    id: "app",
    secret: "secret",
  });
  const first = await client.clientCredentials();
  first.expires_at = Math.floor(Date.now() / 1000) - 60;

  const kept = [];
  const source = client.refreshSource(first, {}, (token) => {
    kept.push(token);
  });

  const renewed = await source.token();
  const again = await source.token();

  assert.equal(renewed, again);
  assert.equal(kept.length, 1);
  assert.notEqual(renewed.refresh_token, first.refresh_token);

  await assert.rejects(client.refresh(first.refresh_token), (error) =>
    hasCode(error, "invalid_grant"),
  );
});

test("concurrent callers share one fetch", async () => {
  const held = await fake();
  held.add("app", { secret: "secret", method: "client_secret_basic" });

  const client = new Client({
    issuer: await Issuer.discover(held.url),
    id: "app",
    secret: "secret",
  });
  const source = client.credentialsSource();
  const [one, two] = await Promise.all([source.token(), source.token()]);

  assert.equal(one, two);
});

test("revocation sends the token", async () => {
  const held = await fake();
  held.add("app", { secret: "secret", method: "client_secret_basic" });

  const client = new Client({
    issuer: await Issuer.discover(held.url),
    id: "app",
    secret: "secret",
  });
  await client.revoke("a-token", "refresh_token");

  assert.deepEqual(held.revoked, ["a-token"]);
});

test("registration with an initial access token", async () => {
  const held = await fake();
  held.initial.set("one-time", "enrolled");

  const issuer = await Issuer.discover(held.url);
  const key = await Key.generate();

  const registration = await issuer.register(
    {
      client_name: "A machine",
      grant_types: ["client_credentials"],
      token_endpoint_auth_method: "private_key_jwt",
      jwks: key.jwks(),
      scope: "files:read",
    },
    "one-time",
  );

  await assert.rejects(issuer.register({}, "one-time"), (error) =>
    hasCode(error, "invalid_token"),
  );

  const read = await issuer.readRegistration(registration);
  assert.equal(
    read.registration_access_token,
    registration.registration_access_token,
  );
  assert.equal(read.token_endpoint_auth_method, "private_key_jwt");

  const updated = await issuer.updateRegistration(read, {
    scope: "files:read files:write",
  });
  const token = await issuer.client(updated, key).clientCredentials();
  assert.equal(token.scope, "files:read files:write");

  await issuer.deleteRegistration(updated);
  await assert.rejects(issuer.readRegistration(updated), (error) =>
    hasCode(error, "invalid_token"),
  );
});

test("a registration URI on another origin never sees the token", async () => {
  const held = await fake();
  held.initial.set("one-time", "enrolled");
  held.foreignURI = true;

  const issuer = await Issuer.discover(held.url);

  await assert.rejects(issuer.register({}, "one-time"), Foreign);
});

test("introspection describes an active token", async () => {
  const held = await fake();
  const { client } = await signedClient(held);
  const description = {
    active: true,
    scope: "files:read",
    client_id: "machine",
    sub: "ada",
    aud: held.audience,
    iss: held.url,
    exp: Math.floor(Date.now() / 1000) + 60,
    tenant: { subdomain: "acme" },
  };
  held.described.set("live", description);

  const found = await client.introspect("live", "access_token");

  assert.deepEqual(found, description);
  assert.ok(hasScope(found, "files:read"));
  assert.deepEqual(held.hints, ["access_token"]);
});

test("introspection reports anything short of active as inactive", async () => {
  const held = await fake();
  const { client } = await signedClient(held);
  held.described.set("stringly", {
    active: "true",
    scope: "files:read",
    sub: "ada",
  });
  held.described.set("ended", { active: false, scope: "files:read" });

  for (const token of ["stringly", "ended", "unknown"]) {
    const found = await client.introspect(token);

    assert.deepEqual(found, { active: false }, token);
    assert.ok(!hasScope(found, "files:read"), token);
  }

  assert.deepEqual(held.hints, [null, null, null]);
  await assert.rejects(client.introspect(""), /names a token/);
});

test("introspection refuses a description from another issuer", async () => {
  const held = await fake();
  const { client } = await signedClient(held);
  held.described.set("foreign", {
    active: true,
    iss: "https://elsewhere.example",
  });

  await assert.rejects(client.introspect("foreign"), (error) =>
    hasCode(error, "invalid_issuer"),
  );
});

test("introspection authenticates the client", async () => {
  const held = await fake();
  held.add("machine", { secret: "right", method: "client_secret_basic" });

  const client = new Client({
    issuer: await Issuer.discover(held.url),
    id: "machine",
    secret: "wrong",
  });

  await assert.rejects(client.introspect("live"), (error) =>
    hasCode(error, "invalid_client"),
  );
});

test("a token exchange sends what it asks for and holds the token to its key", async () => {
  const held = await fake();
  held.nonce = "exchange-nonce";
  const { client, dpop, issuer } = await signedClient(held);

  const token = await client.exchange("subject", {
    subjectTokenType: ID_TOKEN_TYPE,
    actorToken: "actor",
    requestedTokenType: ACCESS_TOKEN_TYPE,
    audience: ["https://calendar.example"],
    scope: ["files:read", "files:write"],
    lifetime: 300,
    resource: [held.audience, "https://other.example"],
  });

  assert.equal(token.token_type, "DPoP");
  assert.equal(token.issued_token_type, ACCESS_TOKEN_TYPE);
  assert.ok(token.expires_at > Date.now() / 1000);
  assert.deepEqual(held.exchanges.at(-1), {
    scope: "files:read files:write",
    resource: [held.audience, "https://other.example"],
    grant_type: GRANT_TOKEN_EXCHANGE,
    subject_token: "subject",
    subject_token_type: ID_TOKEN_TYPE,
    actor_token: "actor",
    actor_token_type: ACCESS_TOKEN_TYPE,
    requested_token_type: ACCESS_TOKEN_TYPE,
    audience: "https://calendar.example",
    requested_lifetime: "300",
    dpop: dpop.thumbprint,
  });

  const claims = await new Verifier(issuer, held.audience).verify(
    token.access_token,
  );
  assert.equal(claims.cnf.jkt, dpop.thumbprint);
});

test("a token exchange names an access token by default and no actor", async () => {
  const held = await fake();
  held.add("machine", {
    secret: "secret",
    method: "client_secret_basic",
  });

  const client = new Client({
    issuer: await Issuer.discover(held.url),
    id: "machine",
    secret: "secret",
  });
  const token = await client.exchange("subject");

  assert.equal(token.token_type, "Bearer");
  assert.deepEqual(held.exchanges.at(-1), {
    grant_type: GRANT_TOKEN_EXCHANGE,
    subject_token: "subject",
    subject_token_type: ACCESS_TOKEN_TYPE,
    dpop: "",
  });

  await assert.rejects(client.exchange(""), /subject token/);
  await assert.rejects(
    client.exchange("subject", { lifetime: 0 }),
    /whole number/,
  );
  assert.equal(held.exchanges.length, 1);
});

test("an upstream token comes back as a Bearer token to a DPoP client", async () => {
  const held = await fake();
  const { client } = await signedClient(held);

  const token = await client.exchange("subject", {
    requestedTokenType: UPSTREAM_ACCESS_TOKEN_TYPE,
    audience: ["connection-1"],
  });

  assert.equal(token.access_token, "from-the-provider");
  assert.equal(token.token_type, "Bearer");
  assert.equal(token.issued_token_type, UPSTREAM_ACCESS_TOKEN_TYPE);
});

test("only an upstream token is excused from being held to the key", async () => {
  const held = await fake();
  const { client } = await signedClient(held);
  held.upstreamAnswer = "access";

  await assert.rejects(
    client.exchange("subject", {
      requestedTokenType: UPSTREAM_ACCESS_TOKEN_TYPE,
    }),
    /another kind of token/,
  );
});

test("an app enrolls a machine that registers itself", async () => {
  const held = await fake();
  const { client, issuer } = await signedClient(held);

  const enrollment = await client.enroll({
    scope: ["xixo:agent"],
    name: "nas",
    expiresIn: 900,
  });

  assert.equal(enrollment.scope, "xixo:agent");
  assert.equal(enrollment.expires_in, 900);
  assert.ok(enrollment.expires_at > Date.now() / 1000);
  assert.deepEqual(held.enrollments.at(-1), {
    app: "signed",
    scope: "xixo:agent",
    name: "nas",
    expires_in: "900",
    dpop: undefined,
  });

  const machineKey = await Key.generate();
  const registration = await issuer.register(
    { client_name: "nas", jwks: machineKey.jwks() },
    enrollment.initial_access_token,
  );

  assert.equal(held.enrolled.get(registration.client_id), "signed");
});

test("an enrollment needs a scope and a lifetime in whole seconds", async () => {
  const held = await fake();
  const { client } = await signedClient(held);

  await assert.rejects(client.enroll({ scope: [] }), /at least one scope/);
  await assert.rejects(
    client.enroll({ scope: ["xixo:agent"], expiresIn: 1.5 }),
    /whole number/,
  );
  assert.equal(held.enrollments.length, 0);
});

test("an enrollment without a token is refused", async () => {
  let base = "";
  const server = await listen((request, response) => {
    if (request.url === "/.well-known/openid-configuration") {
      return json(response, 200, {
        issuer: base,
        enrollment_endpoint: `${base}/enrollments`,
      });
    }

    json(response, 201, { scope: "xixo:agent", expires_in: 900 });
  });
  base = server.url;
  closers.push(server.close);

  const client = new Client({
    issuer: await Issuer.discover(server.url),
    id: "app",
    secret: "secret",
  });

  await assert.rejects(
    client.enroll({ scope: ["xixo:agent"] }),
    /without an initial access token/,
  );
});

test("an app unenrolls only the machines it enrolled", async () => {
  const held = await fake();
  const { client, issuer } = await signedClient(held);
  held.add("other", { secret: "secret", method: "client_secret_basic" });

  const { initial_access_token } = await client.enroll({
    scope: ["xixo:agent"],
  });
  const machine = await issuer.register(
    { jwks: (await Key.generate()).jwks() },
    initial_access_token,
  );

  const other = new Client({ issuer, id: "other", secret: "secret" });

  await assert.rejects(other.unenroll(machine.client_id), (error) => {
    assert.equal(error.code, "invalid_request");
    assert.equal(error.status, 404);
    return true;
  });
  assert.ok(held.clients.has(machine.client_id));

  await client.unenroll(machine.client_id);
  assert.ok(!held.clients.has(machine.client_id));

  await client.unenroll(machine.client_id);
  await assert.rejects(client.unenroll(""), /client_id/);
});

test("unenrolling escapes the machine's client_id", async () => {
  const seen = [];
  let base = "";
  const server = await listen((request, response) => {
    if (request.url === "/.well-known/openid-configuration") {
      return json(response, 200, {
        issuer: base,
        enrollment_endpoint: `${base}/enrollments`,
      });
    }

    seen.push([request.method, request.url]);
    response.writeHead(204);
    response.end();
  });
  base = server.url;
  closers.push(server.close);

  const client = new Client({
    issuer: await Issuer.discover(server.url),
    id: "app",
    secret: "secret",
  });

  await client.unenroll("../token?x=1");

  assert.deepEqual(seen, [["DELETE", "/enrollments/..%2Ftoken%3Fx%3D1"]]);
});

test("keys survive JSON", async () => {
  const key = await Key.generate();
  const encoded = JSON.stringify(key);

  assert.match(encoded, /"d":/);
  assert.doesNotMatch(JSON.stringify(key.publicJWK), /"d":/);
  assert.doesNotMatch(JSON.stringify(key.jwks()), /"d":/);

  const read = await Key.import(encoded);
  assert.equal(read.thumbprint, key.thumbprint);

  await assert.rejects(Key.import(key.publicJWK));
});

async function resource(issuer, audience) {
  const verifier = new Verifier(issuer, audience);
  const seen = [];
  const server = await listen(async (request, response) => {
    try {
      const claims = await verifier.authenticateNode(request);
      seen.push(claims);

      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);

      response.writeHead(200);
      response.end(Buffer.concat(chunks));
    } catch (error) {
      response.writeHead(401, {
        "www-authenticate": verifier.challengeHeaders(error),
      });
      response.end();
    }
  });
  closers.push(server.close);

  return { url: server.url, seen };
}

test("a signed fetch signs each request for its resource", async () => {
  const held = await fake();
  const { client, issuer } = await signedClient(held);
  const files = await resource(issuer, held.audience);

  const signed = client.fetch(
    client.credentialsSource({ resource: [held.audience] }),
    [files.url],
  );

  for (const body of ["one", "two"]) {
    const response = await signed(`${files.url}/files?path=x`, {
      method: "POST",
      body,
    });

    assert.equal(
      response.status,
      200,
      response.headers.get("www-authenticate") ?? "",
    );
    assert.equal(await response.text(), body);
  }

  assert.equal(files.seen.length, 2);
  assert.equal(files.seen[0].sub, "signed");
});

test("a signed fetch refuses an origin it was not given", async () => {
  const held = await fake();
  const { client } = await signedClient(held);

  const signed = client.fetch(client.credentialsSource(), [
    "https://files.example",
  ]);

  await assert.rejects(signed(`${held.url}/elsewhere`), Foreign);
});

test("a signed fetch hands a redirect back without following it", async () => {
  const held = await fake();
  const { client } = await signedClient(held);
  const server = await listen((_, response) => {
    response.writeHead(302, { location: `${held.url}/stolen` });
    response.end();
  });
  closers.push(server.close);

  const signed = client.fetch(client.credentialsSource(), [server.url]);
  const response = await signed(server.url);

  assert.equal(response.status, 302);
  await assert.rejects(signed(response.headers.get("location")), Foreign);
});

test("a signed fetch sends a Bearer token when the token is not held", async () => {
  const held = await fake();
  held.add("app", {
    secret: "secret",
    method: "client_secret_basic",
    scope: "files:read files:write",
  });

  const issuer = await Issuer.discover(held.url);
  const client = new Client({ issuer, id: "app", secret: "secret" });
  const files = await resource(issuer, held.audience);

  const response = await client.fetch(client.credentialsSource(), [files.url])(
    files.url,
  );

  assert.equal(response.status, 200);
  assert.ok(hasScope(files.seen[0], "files:write"));
  assert.equal(files.seen[0].cnf, undefined);
});

test("a signed fetch answers a resource nonce and replays the body", async () => {
  const held = await fake();
  const { client } = await signedClient(held);
  const nonces = [];
  const bodies = [];

  const server = await listen(async (request, response) => {
    const claims = JSON.parse(
      Buffer.from(request.headers.dpop.split(".")[1], "base64url").toString(),
    );
    nonces.push(claims.nonce ?? "");

    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    bodies.push(Buffer.concat(chunks).toString());

    if (claims.nonce !== "server-nonce") {
      response.writeHead(401, {
        "dpop-nonce": "server-nonce",
        "www-authenticate": 'DPoP error="use_dpop_nonce"',
      });
      return response.end();
    }

    response.writeHead(200);
    response.end();
  });
  closers.push(server.close);

  const signed = client.fetch(client.credentialsSource(), [server.url]);

  const response = await signed(server.url, {
    method: "POST",
    body: "payload",
  });
  assert.equal(response.status, 200);
  assert.deepEqual(nonces, ["", "server-nonce"]);
  assert.equal(bodies[1], "payload");

  await signed(server.url, { method: "POST", body: "later" });
  assert.equal(nonces[2], "server-nonce");
});

async function boundRequest(client, dpop, method, target, change) {
  const token = await client.clientCredentials();
  const headers = {
    authorization: `DPoP ${token.access_token}`,
    dpop: await proof(dpop, method, target, token.access_token),
  };

  const held = { method, target, headers, token };
  if (change) await change(held);

  return new Request(held.target, {
    method: held.method,
    headers: held.headers,
  });
}

test("a verifier refuses misused proofs", async () => {
  const held = await fake();
  const { client, dpop, issuer } = await signedClient(held);
  const verifier = new Verifier(issuer, held.audience);
  const target = "http://files.example/files";

  const good = await boundRequest(client, dpop, "GET", target);

  await verifier.authenticate(good);
  await assert.rejects(verifier.authenticate(good), /already been used/);

  const cases = {
    Bearer: (request) => {
      request.headers.authorization = `Bearer ${request.token.access_token}`;
    },
    "no proof": (request) => {
      delete request.headers.dpop;
    },
    "two proofs": (request) => {
      request.headers.dpop = `${request.headers.dpop}, ${request.headers.dpop}`;
    },
    "another method": (request) => {
      request.method = "DELETE";
    },
    "another URL": (request) => {
      request.target = "http://files.example/other";
    },
    "another key": async (request) => {
      const other = await Key.generate();
      request.headers.dpop = await proof(
        other,
        "GET",
        target,
        request.token.access_token,
      );
    },
    "another token": async (request) => {
      request.headers.dpop = await proof(dpop, "GET", target, "something else");
    },
  };

  for (const [name, change] of Object.entries(cases)) {
    const request = await boundRequest(client, dpop, "GET", target, change);

    await assert.rejects(verifier.authenticate(request), InvalidToken, name);
  }
});

test("a verifier asks its replay store once per proof", async () => {
  const held = await fake();
  const { client, dpop, issuer } = await signedClient(held);
  const seen = new Set();
  const asked = [];
  const replay = {
    async first(key, expiresIn) {
      asked.push([key, expiresIn]);
      await new Promise((resolve) => setTimeout(resolve, 1));

      if (seen.has(key)) return false;

      seen.add(key);
      return true;
    },
  };
  const verifier = new Verifier(issuer, held.audience, { replay });
  const target = "http://files.example/files";

  const good = await boundRequest(client, dpop, "GET", target);

  await verifier.authenticate(good);
  await assert.rejects(verifier.authenticate(good), /already been used/);

  assert.equal(asked.length, 2);
  assert.match(asked[0][0], new RegExp(`^${dpop.thumbprint}:.+`));
  assert.equal(asked[0][1], 120);
  assert.equal(verifier.replay, replay);
});

test("a failing replay store is unavailable, and only false is a replay", async () => {
  const held = await fake();
  const { client, dpop, issuer } = await signedClient(held);
  const target = "http://files.example/files";
  const refused = new Error("redis at 10.0.0.4 refused the connection");

  const stores = {
    throws: {
      first() {
        throw refused;
      },
    },
    rejects: { first: async () => Promise.reject(refused) },
    "answers something truthy": { first: async () => "OK" },
    "answers nothing": { first: async () => undefined },
  };

  for (const [name, replay] of Object.entries(stores)) {
    const verifier = new Verifier(issuer, held.audience, { replay });
    const request = await boundRequest(client, dpop, "GET", target);

    const error = await verifier.authenticate(request).then(
      () => assert.fail(name),
      (failed) => failed,
    );

    assert.ok(error instanceof Unavailable, name);
    assert.ok(!(error instanceof InvalidToken), name);
    if (name === "throws" || name === "rejects") {
      assert.equal(error.cause, refused, name);
    }

    const response = verifier.challenge(error);
    assert.equal(response.status, 503, name);
    assert.equal(response.headers.get("www-authenticate"), null, name);
    assert.doesNotMatch(await response.text(), /10\.0\.0\.4/, name);
    assert.deepEqual(verifier.challengeHeaders(error), [], name);
    assert.deepEqual(
      verifier.refusal(error),
      { status: 503, headers: {} },
      name,
    );
  }

  const verifier = new Verifier(issuer, held.audience, {
    replay: { first: async () => false },
  });
  const request = await boundRequest(client, dpop, "GET", target);

  const error = await verifier.authenticate(request).then(
    () => assert.fail("a replay was accepted"),
    (failed) => failed,
  );

  assert.ok(error instanceof InvalidToken);
  assert.match(error.message, /already been used/);

  const { status, headers } = verifier.refusal(error);
  assert.equal(status, 401);
  assert.equal(headers["www-authenticate"].length, 2);
  assert.equal(verifier.challenge(error).status, 401);
});

test("an issuer whose keys cannot be fetched is unavailable", async () => {
  let base = "";
  let keys = 0;
  const server = await listen((request, response) => {
    if (request.url === "/.well-known/openid-configuration") {
      return json(response, 200, {
        issuer: base,
        jwks_uri: `${base}/.well-known/jwks.json`,
      });
    }

    keys++;
    response.writeHead(502);
    response.end();
  });
  base = server.url;
  closers.push(server.close);

  const held = await fake();
  const token = await held.accessToken("machine", "files:read");
  const verifier = new Verifier(
    await Issuer.discover(server.url),
    held.audience,
  );

  await assert.rejects(
    verifier.authenticate(
      new Request("http://files.example/files", {
        headers: { authorization: `Bearer ${token}` },
      }),
    ),
    (error) => {
      assert.ok(error instanceof Unavailable);
      assert.ok(error.cause instanceof MasksError);
      assert.equal(verifier.challenge(error).status, 503);
      return true;
    },
  );
  assert.equal(keys, 1);
});

test("any error that is not a token rejection is unavailable", () => {
  const held = { status: 503, headers: {} };

  for (const error of [
    new Error("boom"),
    new MasksError("server_error"),
    "x",
  ]) {
    const verifier = Object.create(Verifier.prototype);

    assert.deepEqual(verifier.refusal(error), held);
  }
});

test("a bearer token never reaches the replay store", async () => {
  const held = await fake();
  const issuer = await Issuer.discover(held.url);
  const replay = {
    first() {
      throw new Error("not for bearer tokens");
    },
  };
  const verifier = new Verifier(issuer, held.audience, { replay });
  const token = await held.accessToken("machine", "files:read");

  const claims = await verifier.authenticate(
    new Request("http://files.example/files", {
      headers: { authorization: `Bearer ${token}` },
    }),
  );

  assert.equal(claims.sub, "machine");
});

test("the memory replay store forgets a key once it expires", async () => {
  const store = new MemoryReplayStore();

  assert.equal(store.first("a", 60), true);
  assert.equal(store.first("a", 60), false);
  assert.equal(store.first("b", 0.001), true);

  await new Promise((resolve) => setTimeout(resolve, 5));

  assert.equal(store.first("b", 60), true);
  assert.equal(store.first("a", 60), false);
});

test("a verifier checks the token itself", async () => {
  const held = await fake();
  const issuer = await Issuer.discover(held.url);
  const verifier = new Verifier(issuer, held.audience);
  const now = Math.floor(Date.now() / 1000);
  const good = {
    iss: held.url,
    sub: "ada",
    aud: held.audience,
    jti: "1",
    exp: now + 3600,
    iat: now,
  };

  await verifier.verify(await held.issue(good, "at+jwt"));

  const without = (name) => {
    const copy = { ...good };
    delete copy[name];
    return copy;
  };

  const cases = {
    "another audience": [
      await held.issue({ ...good, aud: "https://other.example" }, "at+jwt"),
      "that token was issued for another app",
    ],
    "another issuer": [
      await held.issue({ ...good, iss: "https://other.example" }, "at+jwt"),
      "that token was issued by another server",
    ],
    expired: [
      await held.issue({ ...good, exp: now - 3600 }, "at+jwt"),
      "that token has expired",
    ],
    "no jti": [
      await held.issue(without("jti"), "at+jwt"),
      "that token is missing jti",
    ],
    "an ID token": [
      await held.issue(good, "JWT"),
      "that token is typed JWT, not at+jwt",
    ],
    "not a JWT": ["nonsense", "that token is not a signed JWT"],
  };

  for (const [name, [token, said]] of Object.entries(cases)) {
    await assert.rejects(
      verifier.verify(token),
      (error) =>
        error instanceof InvalidToken &&
        error.message === `masks: invalid_token: ${said}`,
      name,
    );
  }

  const forged = await Key.generate();
  await assert.rejects(
    verifier.verify(await forged.sign("at+jwt", good, false)),
    InvalidToken,
  );
});

test("a request with no token is challenged with no error code", async () => {
  const held = await fake();
  const verifier = new Verifier(await Issuer.discover(held.url), held.audience);

  const error = await verifier
    .authenticate(new Request("https://api.example/files"))
    .then(
      () => assert.fail("a request with no token was accepted"),
      (failed) => failed,
    );

  assert.ok(error instanceof InvalidToken);
  assert.ok(error.missing);

  const [bearer, dpop] = verifier.challengeHeaders(error);

  assert.equal(bearer, "Bearer");
  assert.match(dpop, /^DPoP algs="/);
  assert.doesNotMatch(dpop, /error/);
});

test("a challenge names both schemes", async () => {
  const held = await fake();
  const verifier = new Verifier(await Issuer.discover(held.url), held.audience);

  const response = verifier.challenge(new InvalidToken('a "quoted" reason'));

  assert.equal(response.status, 401);
  assert.match(
    response.headers.get("www-authenticate"),
    /^Bearer error="invalid_token".*DPoP/,
  );
  assert.doesNotMatch(response.headers.get("www-authenticate"), /"quoted"/);
});

test("resource discovery finds the issuer", async () => {
  let base = "";
  const server = await listen((request, response) => {
    if (request.url !== "/.well-known/oauth-protected-resource") {
      response.writeHead(404);
      return response.end();
    }

    json(response, 200, {
      resource: base,
      authorization_servers: ["https://id.example"],
    });
  });
  base = server.url;
  closers.push(server.close);

  const found = await discoverResource(server.url);

  assert.deepEqual(found.authorization_servers, ["https://id.example"]);
});
