import assert from "node:assert/strict";
import { test } from "node:test";
import {
  InsecureError,
  redisStore,
  replayStore,
  upstashStore,
} from "../dist/index.js";

function fakeRedis() {
  const held = new Map();
  const sent = [];
  const live = (key) => {
    const found = held.get(key);

    if (found && found.until <= Date.now()) held.delete(key);

    return held.get(key);
  };

  const send = async (command) => {
    sent.push(command);

    const [name, key, value, ...rest] = command;

    switch (name) {
      case "GET":
        return live(key)?.value ?? null;
      case "DEL":
        return held.delete(key) ? 1 : 0;
      case "SET": {
        const only = rest.includes("NX");
        const seconds = Number(rest[rest.indexOf("EX") + 1]);

        if (only && live(key)) return null;

        held.set(key, { value, until: Date.now() + seconds * 1000 });

        return "OK";
      }
      default:
        throw new Error(`unknown command ${name}`);
    }
  };

  return { send, sent };
}

test("a Redis store adds a key once, sets it with an expiry, and deletes it", async () => {
  const redis = fakeRedis();
  const store = redisStore(redis.send);

  assert.equal(await store.add("claim", "1", 30), true);
  assert.equal(await store.add("claim", "2", 30), false);
  assert.equal(await store.get("claim"), "1");

  await store.set("result", "sealed", 0.2);
  assert.equal(await store.get("result"), "sealed");
  await store.delete("result");
  assert.equal(await store.get("result"), undefined);

  assert.deepEqual(redis.sent[0], ["SET", "claim", "1", "NX", "EX", "30"]);
  assert.deepEqual(redis.sent[3], ["SET", "result", "sealed", "EX", "1"]);
});

test("a Redis store reads a value a client hands back as bytes", async () => {
  const store = redisStore(async () => new TextEncoder().encode("held"));

  assert.equal(await store.get("key"), "held");
});

test("a replay store over a Redis store accepts each proof once", async () => {
  const redis = fakeRedis();
  const replay = replayStore(redisStore(redis.send));

  assert.equal(await replay.first("thumbprint:jti", 120), true);
  assert.equal(await replay.first("thumbprint:jti", 120), false);
  assert.match(redis.sent[0][1], /^masks:[0-9a-f]{64}$/);
});

test("an Upstash store sends each command to the REST URL with its token", async () => {
  const asked = [];
  const store = upstashStore({
    url: "https://example.upstash.io",
    token: "rest-token",
    fetch: async (url, init) => {
      asked.push({ url, init });

      const [name] = JSON.parse(init.body);

      return Response.json({ result: name === "GET" ? "held" : "OK" });
    },
  });

  assert.equal(await store.add("claim", "1", 30), true);
  assert.equal(await store.get("claim"), "held");

  assert.equal(asked[0].url, "https://example.upstash.io");
  assert.equal(asked[0].init.method, "POST");
  assert.equal(asked[0].init.headers.authorization, "Bearer rest-token");
  assert.deepEqual(JSON.parse(asked[0].init.body), [
    "SET",
    "claim",
    "1",
    "NX",
    "EX",
    "30",
  ]);
});

test("an Upstash store throws when Upstash refuses a command", async () => {
  const store = upstashStore({
    url: "https://example.upstash.io",
    token: "wrong",
    fetch: async () =>
      Response.json({ error: "WRONGPASS invalid password" }, { status: 401 }),
  });

  await assert.rejects(store.get("key"), /Upstash refused GET/);
});

test("an Upstash store needs its URL and token, and https away from this machine", () => {
  assert.throws(
    () => upstashStore({ url: "https://example.upstash.io" }),
    /UPSTASH_REDIS_REST_TOKEN/,
  );
  assert.throws(
    () => upstashStore({ url: "http://example.upstash.io", token: "t" }),
    InsecureError,
  );
  assert.ok(upstashStore({ url: "http://localhost:8079", token: "t" }));
});

test("requireAuth takes a page to return to before its privileges", async () => {
  const { requireArguments } = await import("../dist/app/requests.js");

  assert.deepEqual(requireArguments(["admin", "billing"]), {
    privileges: ["admin", "billing"],
  });
  assert.deepEqual(
    requireArguments([{ returnTo: "/reports?year=2026" }, "admin"]),
    {
      returnTo: "/reports?year=2026",
      privileges: ["admin"],
    },
  );
  assert.deepEqual(requireArguments([{ returnTo: "https://evil.example/" }]), {
    returnTo: undefined,
    privileges: [],
  });
});
