# @masks/client

An OIDC client for masks, in the browser. Two modes, because a single-page app has two honest ways to
hold a token and they have different threat models.

```sh
npm install @masks/client
```

## Session mode — a backend-for-frontend holds the tokens

The browser holds a cookie; your server holds the tokens and never hands them down. Nothing sensitive
reaches JavaScript, which is the mode to reach for when you have a backend at all.

```js
import { createSession } from "@masks/client";

const auth = createSession({ basePath: "/auth" });

const account = await auth.session();
if (!account) auth.login({ returnTo: "/dashboard" });

await auth.logout({ everywhere: true });
```

`require()` resolves with the account or redirects, `status()` reports what the server knows without
throwing, and `handshake()` starts the connect flow. CSRF tokens are read from a
`meta[name="csrf-token"]` tag unless you pass `csrfToken`.

## Browser mode — the code flow with PKCE, in the page

No backend, so the page runs the flow itself and holds the tokens.

```js
import { createBrowserClient } from "@masks/client";

const auth = createBrowserClient({
  issuer: "https://auth.example.com",
  clientId: "...",
  redirectUri: "https://app.example.com/callback",
  scope: ["openid", "profile"],
  resource: "https://api.example.com",
});

if (auth.pending()) {
  const { identity, returnTo } = await auth.callback();
}

await auth.authorize({ returnTo: "/dashboard" });
```

Discovery, the PKCE challenge, state and nonce, the callback exchange and refresh are all handled.
`accessToken()` and `authorization()` give you something to attach to a request; `expired(leeway)`
tells you when to refresh first.

## Avatars

Every actor has three faces at once — an uploaded `photo`, an `identicon`, and two-letter
`initials` — and the token carries all three. A photo needs a token, so the two modes differ.

```js
const account = await auth.session();

img.src = auth.avatarUrl(account, { size: 64 });
```

In session mode `avatarUrl` returns your backend's proxy path for the photo and the issuer's URL for
a generated style, so no token reaches the page. In browser mode the page holds the token, so the
photo comes back as a blob:

```js
const blob = await auth.photo();

img.src = blob
  ? URL.createObjectURL(blob)
  : await auth.avatarUrl(subject, { style: "identicon" });
```

`avatars()` reads the three URLs straight off the id token. Sizes are 32, 64, 128, 256 or 512.

## Audiences

Pass `resource` to name the API the token is for. Every token names the API it was issued for and is
rejected elsewhere, so one leaked token does not open everything — pass an array when a page talks to
more than one.

## Verifying an id token

```js
import { verifyIdToken } from "@masks/client";
```

Signature, issuer, audience, expiry and nonce, against the issuer's JWKS.

Errors are `MasksError`. Types — `Account`, `Claims`, `Discovery`, `Refusal`, `Status`, `Tenant`,
`Tokens` — are exported alongside the functions.

## The other half

A Ruby or Rails app signs in against the same issuer with the [`masks`](https://rubygems.org/gems/masks)
gem, which carries the Rails engine that mounts the consumer side of the code flow. This package
exists because an SPA is a consumer the engine cannot serve: the engine redirects.

MIT.
