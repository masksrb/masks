import assert from "node:assert/strict";
import { after, mock, test } from "node:test";
import { IssuerCache } from "../dist/app/issuers.js";
import { Issuer, UnavailableError } from "../dist/index.js";
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
    await assert.rejects(issuer.key("unknown"), UnavailableError);
    assert.equal(fetched(), 2);

    mock.timers.tick(60 * 60 * 1000);
    await assert.rejects(issuer.key(kid));
  } finally {
    mock.timers.reset();
  }
});
