import assert from "node:assert/strict";
import { readFileSync, rmSync, writeFileSync } from "node:fs";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { compile } from "svelte/compiler";
import { render } from "svelte/server";

const source = readFileSync(
  new URL("../src/svelte/Person.svelte", import.meta.url),
  "utf8",
);
const { js } = compile(source, {
  generate: "server",
  filename: "Person.svelte",
});

const compiledPath = fileURLToPath(
  new URL("../dist/svelte/Person.server.test.js", import.meta.url),
);
writeFileSync(compiledPath, js.code);

const { default: Person } = await import(`${compiledPath}?t=${Date.now()}`);

rmSync(compiledPath);

const ACCOUNT = {
  signed_in: true,
  name: "Ada Lovelace",
  nickname: "ada",
  email: "ada@example.com",
  scopes: ["openid", "masks:manage"],
};

test("the svelte Person server-renders with no window in sight, same shape as the react one", () => {
  const { body } = render(Person, {
    props: {
      account: ACCOUNT,
      avatarUrl: "https://masks.test/avatars/a/photo/x",
    },
  });

  assert.match(body, /Ada Lovelace/);
  assert.match(body, /@ada · ada@example\.com/);
  assert.match(body, /Manager/);
  assert.match(
    body,
    /<img[^>]*src="https:\/\/masks\.test\/avatars\/a\/photo\/x"/,
  );
});

test("with no avatar it falls back to initials, and a sign-out button appears only when asked for", () => {
  const { body: withoutSignOut } = render(Person, {
    props: { account: ACCOUNT },
  });
  const { body: withSignOut } = render(Person, {
    props: { account: ACCOUNT, onSignOut: () => {}, signOutLabel: "Leave" },
  });

  assert.match(withoutSignOut, /masks-person-avatar-letters/);
  assert.match(withoutSignOut, />\s*AL\s*</);
  assert.doesNotMatch(withoutSignOut, /masks-person-signout/);
  assert.match(withSignOut, /masks-person-signout/);
  assert.match(withSignOut, />\s*Leave\s*</);
});

test("the svelte Person names the organization and the role held in it", () => {
  const { body } = render(Person, {
    props: {
      account: {
        ...ACCOUNT,
        organization: {
          id: "org-1",
          key: "acme",
          name: "Acme",
          role: "billing",
        },
      },
    },
  });

  assert.match(body, /masks-person-org/);
  assert.match(body, /Acme/);
  assert.match(body, /billing/);
  assert.doesNotMatch(
    render(Person, { props: { account: ACCOUNT } }).body,
    /masks-person-org/,
  );
});

test("the svelte Person offers the other organizations only when it can switch", () => {
  const acme = { id: "org-1", key: "acme", name: "Acme", role: "owner" };
  const globex = { id: "org-2", key: "globex", name: "Globex", role: "member" };
  const account = {
    ...ACCOUNT,
    organization: acme,
    organizations: [acme, globex],
  };

  const { body } = render(Person, {
    props: { account, onSwitchOrganization: () => {} },
  });

  assert.match(body, /masks-person-orgs/);
  assert.match(body, /masks-person-switch[^>]*>\s*Globex/);
  assert.doesNotMatch(body, /masks-person-switch[^>]*>\s*Acme/);
  assert.doesNotMatch(
    render(Person, { props: { account } }).body,
    /masks-person-orgs/,
  );
});
