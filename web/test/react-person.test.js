import assert from "node:assert/strict";
import { test } from "node:test";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { Person } from "../dist/react/index.js";

const ACCOUNT = {
  signed_in: true,
  name: "Ada Lovelace",
  nickname: "ada",
  email: "ada@example.com",
  scopes: ["openid", "masks:manage"],
};

test("the react Person renders server-side with no window in sight", () => {
  const html = renderToStaticMarkup(
    createElement(Person, {
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
    createElement(Person, { account: ACCOUNT }),
  );
  const withSignOut = renderToStaticMarkup(
    createElement(Person, {
      account: ACCOUNT,
      onSignOut: () => {},
      signOutLabel: "Leave",
    }),
  );

  assert.match(withoutSignOut, /masks-person-avatar-letters/);
  assert.match(withoutSignOut, />AL</);
  assert.doesNotMatch(withoutSignOut, /masks-person-signout/);
  assert.match(withSignOut, /masks-person-signout/);
  assert.match(withSignOut, />Leave</);
});
