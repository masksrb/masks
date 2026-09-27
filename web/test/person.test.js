import assert from "node:assert/strict";
import { test } from "node:test";
import { holdsRole, initials, personFrom } from "../dist/person.js";

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

test("an organization brings its name and the person's role", () => {
  const account = {
    signed_in: true,
    nickname: "ada",
    scopes: ["openid", "organization"],
    organization: { id: "org-1", key: "acme", name: "Acme", role: "owner" },
  };
  const info = personFrom(account);

  assert.equal(info.organization.name, "Acme");
  assert.equal(info.role, "owner");
  assert.equal(info.owner, true);
  assert.equal(holdsRole(account, "billing", "owner"), true);
  assert.equal(holdsRole(account, "billing"), false);
});

test("with no organization there is no role to hold", () => {
  const account = { signed_in: true, nickname: "ada", scopes: [] };
  const info = personFrom(account);

  assert.equal(info.organization, null);
  assert.equal(info.role, null);
  assert.equal(info.owner, false);
  assert.equal(holdsRole(account, "owner"), false);
});

test("the other organizations are the ones a person can switch to", () => {
  const acme = { id: "org-1", key: "acme", name: "Acme", role: "owner" };
  const globex = { id: "org-2", key: "globex", name: "Globex", role: "member" };
  const info = personFrom({
    signed_in: true,
    name: "Ada",
    scopes: ["openid", "organization"],
    organization: acme,
    organizations: [acme, globex],
  });

  assert.deepEqual(info.organizations, [acme, globex]);
  assert.deepEqual(info.others, [globex]);
  assert.deepEqual(personFrom({ signed_in: true, scopes: [] }).others, []);
});
