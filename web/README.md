<p align="center"><img src="https://raw.githubusercontent.com/masksrb/masks/main/engine/public/masks-public/icon.svg" width="120" alt="The masks rose window"></p>

# @masks/client

`@masks/client` signs people in to a single-page app against
[masks](https://github.com/masksrb/masks), a self-hosted OpenID Connect provider. It runs in the
browser and holds no client secret.

```sh
npm install @masks/client
```

It has two modes.

## Session mode

A backend holds the tokens, and the browser holds only a cookie. Use this mode whenever the app has a
backend that runs a masks SDK, such as `@masks/server`.

```js
import { createSession } from "@masks/client";

const auth = createSession({ basePath: "/auth" });

const account = await auth.session();

if (!account) auth.login({ returnTo: "/dashboard" });
```

## Browser mode

A site with no backend runs the sign-in in the page and keeps the tokens in `sessionStorage`. The
Vite plugin writes a file that names the site to masks, so there is no client to register.

```js
// vite.config.js
import { masks } from "@masks/client/vite";

export default defineConfig({ plugins: [masks({ name: "Catalog" })] });
```

```js
import { createBrowserClient } from "@masks/client";

const auth = createBrowserClient({ issuer: "https://acme.auth.example.com" });

const actor = await auth.ready();

if (!actor) await auth.authorize();
```

Build with `MASKS_ORIGIN` set to the site's public address.

## Showing who is signed in

`Actor` from `@masks/client/react`, or the default export of `@masks/client/svelte`, shows an
account's name, avatar, and a sign-out button. It takes plain data as props, and ships no CSS. Its class names start with
`masks-actor`.

```jsx
import { Actor } from "@masks/client/react";

<Actor
  account={account}
  avatarUrl={auth.avatarUrl(account, { size: 88 })}
  onSignOut={() => auth.logout()}
/>;
```

Without `onSignOut`, no sign-out button shows. `actorFrom` from `@masks/client` reads an account the
same way, for other frameworks.

## Documentation

- [Static sites](https://masks.pages.dev/reference/javascript/static/) sets up browser mode, step by
  step.
- [`@masks/client`](https://masks.pages.dev/reference/javascript/client/) lists every function,
  option, and error.

MIT.
