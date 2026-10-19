import assert from "node:assert/strict";
import { test } from "node:test";
import { unslashed, untrailed } from "../dist/slashes.js";

test("trailing slashes come off, however many there are", () => {
  assert.equal(untrailed("https://id.example/"), "https://id.example");
  assert.equal(untrailed("https://id.example////"), "https://id.example");
  assert.equal(untrailed("https://id.example"), "https://id.example");
  assert.equal(untrailed("////"), "");
  assert.equal(untrailed(""), "");
});

test("a path loses its leading and trailing slashes and keeps the ones inside", () => {
  assert.equal(unslashed("/auth/"), "auth");
  assert.equal(unslashed("///api/auth///"), "api/auth");
  assert.equal(unslashed("auth"), "auth");
  assert.equal(unslashed("/"), "");
});

test("a long run of slashes is trimmed in one pass", () => {
  const long = `${"/".repeat(100000)}a`;
  const started = performance.now();

  assert.equal(unslashed(long), "a");
  assert.ok(performance.now() - started < 200);
});
