import assert from "node:assert/strict";
import { after, test } from "node:test";
import { timing } from "../dist/client.js";
import {
  Client,
  discoverResource,
  ForeignError,
  hasCode,
  hasScope,
  InsecureError,
  InvalidTokenError,
  Issuer,
  Key,
  MasksError,
  proof,
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

  assert.throws(() => check("http://10.0.0.4"), InsecureError);
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

  await assert.rejects(issuer.register({}, "one-time"), ForeignError);
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

  await assert.rejects(signed(`${held.url}/elsewhere`), ForeignError);
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
  await assert.rejects(signed(response.headers.get("location")), ForeignError);
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

    await assert.rejects(
      verifier.authenticate(request),
      InvalidTokenError,
      name,
    );
  }
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
    "another audience": await held.issue(
      { ...good, aud: "https://other.example" },
      "at+jwt",
    ),
    "another issuer": await held.issue(
      { ...good, iss: "https://other.example" },
      "at+jwt",
    ),
    expired: await held.issue({ ...good, exp: now - 3600 }, "at+jwt"),
    "no jti": await held.issue(without("jti"), "at+jwt"),
    "an ID token": await held.issue(good, "JWT"),
    "not a JWT": "nonsense",
  };

  for (const [name, token] of Object.entries(cases)) {
    await assert.rejects(verifier.verify(token), InvalidTokenError, name);
  }

  const forged = await Key.generate();
  await assert.rejects(
    verifier.verify(await forged.sign("at+jwt", good, false)),
    InvalidTokenError,
  );
});

test("a challenge names both schemes", async () => {
  const held = await fake();
  const verifier = new Verifier(await Issuer.discover(held.url), held.audience);

  const response = verifier.challenge(
    new InvalidTokenError('a "quoted" reason'),
  );

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
