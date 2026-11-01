import assert from "node:assert/strict";
import { after, mock, test } from "node:test";
import { IssuerCache } from "../dist/app/issuers.js";
import { Issuer, memoryStore, Unavailable } from "../dist/index.js";
import { Fake } from "./fake.js";

const closers = [];

after(async () => {
  for (const close of closers) await close();
});

function counting() {
  const asked = [];
  let down = false;
  const fetcher = async (input, init) => {
    asked.push(String(input));
    if (down) throw new TypeError("fetch failed");
    return fetch(input, init);
  };

  return {
    asked,
    fetcher,
    down: (value) => {
      down = value;
    },
  };
}

test("a stale issuer is served while one refresh runs, and a failure keeps the last good one", async () => {
  const fake = await Fake.start();
  closers.push(fake.close);
  const net = counting();
  const cache = new IssuerCache(() => ({ fetch: net.fetcher }));

  mock.timers.enable({ apis: ["Date"], now: 0 });

  try {
    const first = await cache.get(fake.url);
    const discoveries = () =>
      net.asked.filter((url) => url.includes("openid-configuration")).length;

    assert.equal(discoveries(), 1);
    assert.equal(await cache.get(fake.url), first);
    assert.equal(discoveries(), 1);

    mock.timers.tick(3_600_001);
    net.down(true);

    assert.equal(await cache.get(fake.url), first);
    assert.equal(await cache.get(fake.url), first);
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(discoveries(), 2);

    assert.equal(await cache.get(fake.url), first);
    assert.equal(discoveries(), 2);

    mock.timers.tick(5_001);
    net.down(false);
    await cache.get(fake.url);
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(discoveries(), 3);
  } finally {
    mock.timers.reset();
  }
});

test("an issuer that cannot be reached is not asked again until the back-off ends", async () => {
  const net = counting();
  const cache = new IssuerCache(() => ({ fetch: net.fetcher }));
  const url = "http://127.0.0.1:1";

  net.down(true);
  mock.timers.enable({ apis: ["Date"], now: 0 });

  try {
    await assert.rejects(cache.get(url));
    await assert.rejects(cache.get(url));
    assert.equal(net.asked.length, 1);

    mock.timers.tick(5_001);
    await assert.rejects(cache.get(url));
    assert.equal(net.asked.length, 2);

    mock.timers.tick(5_001);
    await assert.rejects(cache.get(url));
    assert.equal(net.asked.length, 2);

    mock.timers.tick(5_000);
    await assert.rejects(cache.get(url));
    assert.equal(net.asked.length, 3);
  } finally {
    mock.timers.reset();
  }
});

test("while masks is down, a known key keeps checking tokens and the keys are not fetched on every request", async () => {
  const fake = await Fake.start();
  closers.push(fake.close);
  const net = counting();
  const issuer = await Issuer.discover(fake.url, { fetch: net.fetcher });
  const { keys } = await (
    await fetch(`${fake.url}/.well-known/jwks.json`)
  ).json();
  const kid = keys[0].kid;
  const fetched = () => net.asked.filter((url) => url.includes("jwks")).length;

  mock.timers.enable({ apis: ["Date"], now: Date.now() });

  try {
    assert.equal((await issuer.key(kid)).kid, kid);
    assert.equal(fetched(), 1);

    mock.timers.tick(5 * 60 * 1000 + 1);
    net.down(true);

    assert.equal((await issuer.key(kid)).kid, kid);
    assert.equal(fetched(), 2);
    assert.equal((await issuer.key(kid)).kid, kid);
    await assert.rejects(issuer.key("unknown"), Unavailable);
    assert.equal(fetched(), 2);

    mock.timers.tick(60 * 60 * 1000);
    await assert.rejects(issuer.key(kid));
  } finally {
    mock.timers.reset();
  }
});

test("a rediscovered issuer keeps the keys it already fetched", async () => {
  const fake = await Fake.start();
  closers.push(fake.close);
  const net = counting();
  const cache = new IssuerCache(() => ({ fetch: net.fetcher }));
  const { keys } = await (
    await fetch(`${fake.url}/.well-known/jwks.json`)
  ).json();
  const kid = keys[0].kid;
  const fetched = () => net.asked.filter((url) => url.includes("jwks")).length;

  mock.timers.enable({ apis: ["Date"], now: Date.now() });

  try {
    const first = await cache.get(fake.url);
    await first.key(kid);
    assert.equal(fetched(), 1);

    mock.timers.tick(3_600_001);
    await first.key(kid);
    assert.equal(fetched(), 2);
    await cache.get(fake.url);

    let second = first;
    for (let tries = 0; second === first && tries < 100; tries++) {
      await new Promise((resolve) => setTimeout(resolve, 5));
      second = await cache.get(fake.url);
    }

    assert.notEqual(second, first);
    assert.equal((await second.key(kid)).kid, kid);
    assert.equal(fetched(), 2);
  } finally {
    mock.timers.reset();
  }
});

test("the memory store forgets expired entries and adds a key once", async () => {
  mock.timers.enable({ apis: ["Date"], now: 0 });

  try {
    const store = memoryStore();

    await store.set("abandoned", "x", 1);
    assert.equal(await store.add("claimed", "1", 1), true);
    assert.equal(await store.add("claimed", "2", 1), false);

    mock.timers.tick(61_000);
    await store.set("fresh", "y", 60);

    assert.equal(await store.get("abandoned"), undefined);
    assert.equal(await store.get("fresh"), "y");
    assert.equal(await store.add("claimed", "3", 1), true);
    assert.equal(await store.get("claimed"), "3");

    await store.delete("fresh");
    assert.equal(await store.get("fresh"), undefined);
  } finally {
    mock.timers.reset();
  }
});
