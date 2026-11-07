import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, test } from "node:test";
import { importJWK, SignJWT } from "jose";
import {
  Client,
  failure,
  InvalidToken,
  Issuer,
  Verifier,
} from "../dist/index.js";
import { json, listen } from "./http.js";

const contract = JSON.parse(
  readFileSync(new URL("../../test/contract/tokens.json", import.meta.url)),
);

let server;
let issuer;

function placed(value, names) {
  if (typeof value === "string") {
    return value.replace(/\{[a-z_]+\}/g, (name) => names[name.slice(1, -1)]);
  }

  if (Array.isArray(value)) return value.map((held) => placed(held, names));

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, held]) => [key, placed(held, names)]),
    );
  }

  return value;
}

function merged(base, overrides = {}) {
  const held = { ...base };

  for (const [name, value] of Object.entries(overrides)) {
    if (value === null) delete held[name];
    else held[name] = value;
  }

  return held;
}

function timed(claims) {
  const now = Math.floor(Date.now() / 1000);
  const held = { ...claims };

  for (const name of contract.times) {
    if (typeof held[name] === "number") held[name] += now;
  }

  return held;
}

function encoded(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

async function signed(held, names) {
  if (held.raw !== undefined) return held.raw;

  const base = contract.tokens[held.token];
  const header = merged(base.header, held.header);
  const claims = timed(placed(merged(base.claims, held.claims), names));
  const key = held.key ?? "signing";

  if (key === "none") return `${encoded(header)}.${encoded(claims)}.`;

  const signer =
    key === "secret"
      ? new TextEncoder().encode(contract.secret)
      : await importJWK(contract.keys[key], header.alg);

  return new SignJWT(claims).setProtectedHeader(header).sign(signer);
}

function verify(held, token) {
  const client = new Client({ issuer, id: contract.client_id });
  const expecting = { ...contract.expecting, ...held.expecting };

  switch (held.token) {
    case "access":
      return new Verifier(issuer, contract.resource).verify(token);
    case "id":
      return client.identity(token, {
        nonce: expecting.nonce,
        accessToken: expecting.access_token,
        maxAge: expecting.max_age || undefined,
      });
    case "logout":
      return client.logoutToken(token);
  }

  throw new Error(`no such token kind: ${held.token}`);
}

before(async () => {
  server = await listen((request, response) => {
    const names = { issuer: server.url };

    switch (new URL(request.url, server.url).pathname) {
      case "/.well-known/openid-configuration":
        return json(response, 200, placed(contract.discovery, names));
      case "/.well-known/jwks.json":
        return json(response, 200, contract.jwks);
      default:
        return json(response, 404, { error: "not_found" });
    }
  });

  issuer = await Issuer.discover(server.url);
});

after(() => server.close());

test("every token in the contract ends as the contract says", async (t) => {
  for (const held of contract.cases) {
    await t.test(held.name, async () => {
      const names = {
        issuer: server.url,
        client_id: contract.client_id,
        resource: contract.resource,
      };
      const token = await signed(held, names);

      if (held.outcome === "ok") {
        await verify(held, token);
        return;
      }

      const { code, description } = failure(
        held.outcome.failure,
        ...placed(held.outcome.values ?? [], names),
      );

      await assert.rejects(verify(held, token), (error) => {
        assert.ok(error instanceof InvalidToken, `${error}`);
        assert.equal(error.name, "InvalidToken");
        assert.equal(error.code, code);
        assert.equal(error.description, description);

        return true;
      });
    });
  }
});
