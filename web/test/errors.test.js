import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  failure,
  hasCode,
  Insecure,
  InvalidToken,
  isMasksError,
  MasksError,
  Refused,
} from "../dist/index.js";

const table = JSON.parse(
  readFileSync(new URL("../../test/contract/errors.json", import.meta.url)),
);

const KINDS = { Refused, InvalidToken, Insecure };

test("every kind the browser package has is a MasksError with its own name", () => {
  for (const kind of table.kinds) {
    if (kind.names.web === "") continue;

    assert.equal(kind.names.web, kind.name);
    assert.ok(KINDS[kind.name], kind.name);
  }
});

test("every failure of those kinds is raised with its code and description", () => {
  for (const [key, held] of Object.entries(table.failures)) {
    if (!KINDS[held.kind]) continue;

    const names = held.description.match(/\{[a-z_]+\}/g) ?? [];
    const values = names.map((name) => name.slice(1, -1).toUpperCase());
    const description = names.reduce(
      (text, name, index) => text.replace(name, values[index]),
      held.description,
    );

    assert.deepEqual(failure(key, ...values), { code: held.code, description });

    const error = KINDS[held.kind].of(key, ...values);

    assert.ok(error instanceof MasksError, key);
    assert.ok(isMasksError(error), key);
    assert.equal(error.name, held.kind, key);
    assert.equal(error.code, held.code, key);
    assert.equal(error.description, description, key);
    assert.equal(error.message, `masks: ${held.code}: ${description}`, key);
    assert.ok(hasCode(error, held.code), key);
  }
});
