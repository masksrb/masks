import assert from "node:assert/strict";
import { test } from "node:test";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { Actor } from "../dist/react/index.js";

const ACCOUNT = {
  signed_in: true,
  name: "Ada Lovelace",
  nickname: "ada",
  email: "ada@example.com",
  scopes: ["openid", "masks:manage"],
};

test("the react Actor renders server-side with no window in sight", () => {
  const html = renderToStaticMarkup(
    createElement(Actor, {
      account: ACCOUNT,
      avatarUrl: "https://masks.test/avatars/a/photo/x",
    }),
  );

  assert.match(html, /Ada Lovelace/);
  assert.match(html, /@ada · ada@example\.com/);
  assert.match(html, /Manager/);
  assert.match(
    html,
    /<img[^>]*src="https:\/\/masks\.test\/avatars\/a\/photo\/x"/,
  );
});

test("with no avatar it falls back to initials, and a sign-out button appears only when asked for", () => {
  const withoutSignOut = renderToStaticMarkup(
    createElement(Actor, { account: ACCOUNT }),
  );
  const withSignOut = renderToStaticMarkup(
    createElement(Actor, {
      account: ACCOUNT,
      onSignOut: () => {},
      signOutLabel: "Leave",
    }),
  );

  assert.match(withoutSignOut, /masks-actor-avatar-letters/);
  assert.match(withoutSignOut, />AL</);
  assert.doesNotMatch(withoutSignOut, /masks-actor-signout/);
  assert.match(withSignOut, /masks-actor-signout/);
  assert.match(withSignOut, />Leave</);
});

test("the react Actor names the organization and the role held in it", () => {
  const html = renderToStaticMarkup(
    createElement(Actor, {
      account: {
        ...ACCOUNT,
        organization: {
          id: "org-1",
          key: "acme",
          name: "Acme",
          role: "billing",
        },
      },
    }),
  );

  assert.match(
    html,
    /class="masks-actor-org">Acme<span class="masks-actor-org-role">billing<\/span>/,
  );
  assert.doesNotMatch(
    renderToStaticMarkup(createElement(Actor, { account: ACCOUNT })),
    /masks-actor-org/,
  );
});

test("the react Actor offers the other organizations only when it can switch", () => {
  const acme = { id: "org-1", key: "acme", name: "Acme", role: "owner" };
  const globex = { id: "org-2", key: "globex", name: "Globex", role: "member" };
  const account = {
    ...ACCOUNT,
    organization: acme,
    organizations: [acme, globex],
  };

  const html = renderToStaticMarkup(
    createElement(Actor, { account, onSwitchOrganization: () => {} }),
  );

  assert.match(
    html,
    /class="masks-actor-orgs"><button type="button" class="masks-actor-switch">Globex<\/button>/,
  );
  assert.doesNotMatch(html, /masks-actor-switch">Acme/);
  assert.doesNotMatch(
    renderToStaticMarkup(createElement(Actor, { account })),
    /masks-actor-orgs/,
  );
});
