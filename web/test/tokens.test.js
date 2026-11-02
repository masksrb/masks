import assert from "node:assert/strict";
import { createHmac, createPrivateKey, sign as signBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { failure, InvalidToken, verifyIdToken } from "../dist/index.js";

const contract = JSON.parse(
  readFileSync(new URL("../../test/contract/tokens.json", import.meta.url)),
);
const ISSUER = "https://masks.contract.test";
const NAMES = {
  issuer: ISSUER,
  client_id: contract.client_id,
  resource: contract.resource,
};

function placed(value) {
  if (typeof value === "string") {
    return value.replace(/\{[a-z_]+\}/g, (name) => NAMES[name.slice(1, -1)]);
  }

  if (Array.isArray(value)) return value.map(placed);

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, held]) => [key, placed(held)]),
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

function signed(held) {
  if (held.raw !== undefined) return held.raw;

  const base = contract.tokens[held.token];
  const header = merged(base.header, held.header);
  const claims = timed(placed(merged(base.claims, held.claims)));
  const key = held.key ?? "signing";
  const signing = `${encoded(header)}.${encoded(claims)}`;

  if (key === "none") return `${signing}.`;

  if (key === "secret") {
    const mac = createHmac("sha256", contract.secret).update(signing).digest();

    return `${signing}.${mac.toString("base64url")}`;
  }

  const privateKey = createPrivateKey({
    key: contract.keys[key],
    format: "jwk",
  });
  const signature = signBytes(
    "sha256",
    Buffer.from(signing),
    header.alg === "ES256"
      ? { key: privateKey, dsaEncoding: "ieee-p1363" }
      : privateKey,
  );

  return `${signing}.${signature.toString("base64url")}`;
}

async function keyFor(kid) {
  const found = contract.jwks.keys.find((key) => key.kid === kid);

  if (!found) throw InvalidToken.of("no_key", ISSUER, kid);

  return found;
}

function verify(held, token) {
  const expecting = { ...contract.expecting, ...held.expecting };

  return verifyIdToken(token, {
    issuer: ISSUER,
    audience: contract.client_id,
    nonce: expecting.nonce,
    accessToken: expecting.access_token,
    maxAge: expecting.max_age || undefined,
    keyFor,
  });
}

test("every token in the contract ends as the contract says", async (t) => {
  for (const held of contract.cases.filter((held) => held.token === "id")) {
    await t.test(held.name, async () => {
      const token = signed(held);

      if (held.outcome === "ok") {
        assert.equal((await verify(held, token)).sub, "person-1");
        return;
      }

      const { code, description } = failure(
        held.outcome.failure,
        ...placed(held.outcome.values ?? []),
      );

      await assert.rejects(verify(held, token), (error) => {
        assert.ok(error instanceof InvalidToken, `${error}`);
        assert.equal(error.code, code);
        assert.equal(error.description, description);

        return true;
      });
    });
  }
});
