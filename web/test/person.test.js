import assert from "node:assert/strict";
import { test } from "node:test";
import { initials, personFrom } from "../dist/person.js";

test("a name wins, then a handle, then an email, and nothing repeats", () => {
  const full = personFrom({
    signed_in: true,
    name: "Ada Lovelace",
    nickname: "ada",
    email: "ada@example.com",
    scopes: [],
  });
  const handle = personFrom({
    signed_in: true,
    nickname: "ada",
    email: "ada@example.com",
    scopes: [],
  });
  const bare = personFrom({
    signed_in: true,
    email: "ada@example.com",
    scopes: [],
  });

  assert.deepEqual(
    [full.name, full.details],
    ["Ada Lovelace", ["@ada", "ada@example.com"]],
  );
  assert.deepEqual(
    [handle.name, handle.details],
    ["@ada", ["ada@example.com"]],
  );
  assert.deepEqual([bare.name, bare.details], ["ada@example.com", []]);
});

test("an unconfirmed email is flagged, a confirmed one is not", () => {
  const unconfirmed = personFrom({
    signed_in: true,
    email: "ada@example.com",
    email_verified: false,
    scopes: [],
  });
  const confirmed = personFrom({
    signed_in: true,
    email: "ada@example.com",
    email_verified: true,
    scopes: [],
  });
  const none = personFrom({ signed_in: true, nickname: "ada", scopes: [] });

  assert.equal(unconfirmed.unconfirmed, true);
  assert.equal(confirmed.unconfirmed, false);
  assert.equal(none.unconfirmed, false);
});

test("masks:manage marks someone a manager", () => {
  assert.equal(
    personFrom({
      signed_in: true,
      nickname: "ada",
      scopes: ["openid", "masks:manage"],
    }).manager,
    true,
  );
  assert.equal(
    personFrom({ signed_in: true, nickname: "ada", scopes: ["openid"] })
      .manager,
    false,
  );
});

test("initials falls back gracefully", () => {
  assert.equal(initials("Ada Lovelace"), "AL");
  assert.equal(initials("ada"), "AD");
  assert.equal(initials("ada@example.com"), "AE");
  assert.equal(initials(""), "?");
});
