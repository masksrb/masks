<p align="center"><img src="https://raw.githubusercontent.com/masksrb/masks/main/engine/public/masks-public/icon.svg" width="120" alt="The masks rose window"></p>

# @masks/client

Signs a single-page app in against masks. It has two modes: a backend holds the tokens, or the page
runs the code flow and holds them itself.

```sh
npm install @masks/client
```

## Session mode

The browser holds a cookie, and a backend running the `masks` gem's Rails engine holds the tokens, so
no token reaches JavaScript. Use this mode whenever the app has a backend.

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

## Browser mode

With no backend, the page runs the authorization code flow with PKCE and holds the tokens.

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

The client handles discovery, the PKCE challenge, state and nonce, the callback exchange, and
`refresh()`. `accessToken()` and `authorization()` return what to attach to a request, and
`expired(leeway)` says when to refresh first.

## Avatars

Every account has three avatars: an uploaded `photo`, an `identicon`, and two-letter `initials`, and
the ID token carries all three. A photo needs a token, so the two modes fetch it differently.

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

`avatars()` reads the three URLs from the ID token. Sizes are 32, 64, 128, 256 or 512.

## Who's signed in

`Person` renders an account as a name, a handle or email under it, an unconfirmed-email note, a
manager badge, and an avatar that falls back to initials. It takes plain data as props, so it
renders the same in a browser or on a server.

```jsx
import { Person } from "@masks/client/react";

<Person
  account={account}
  avatarUrl={auth.avatarUrl(account, { size: 88 })}
  onSignOut={() => auth.logout()}
/>;
```

```svelte
<script>
  import Person from "@masks/client/svelte";
</script>

<Person account={account} avatarUrl={auth.avatarUrl(account, { size: 88 })} onSignOut={() => auth.logout()} />
```

Without `onSignOut`, no sign-out button renders. Both components read the account through
`personFrom`, which the package root exports for other frameworks. The class names start with
`masks-person`, and the package ships no CSS.

## Audiences

Pass `resource` to name the API a token is for. Each token is accepted only by the API it names.
Pass an array when a page talks to more than one.

## Verifying an id token

```js
import { verifyIdToken } from "@masks/client";
```

It checks the signature against the issuer's JWKS, and the issuer, audience, expiry, and nonce.

Errors are `MasksError`, and the types are exported beside the functions.

## Documentation

The full reference is generated from this package at
[masks.pages.dev/reference/browser](https://masks.pages.dev/reference/browser/). A Ruby or Rails
app uses the [`masks`](https://rubygems.org/gems/masks) gem.

MIT.
