# @masks/server

`@masks/server` connects a JavaScript server to [masks](https://github.com/masksrb/masks), a
self-hosted OpenID Connect provider.

- It signs people in to a Next.js, Auth.js, Express, or Hono app.
- It gets tokens as a client, for a server or a machine.
- It checks access tokens in an API.

It uses only `fetch`, `Request`, `Response`, and Web Crypto, so it runs on Node 20 and later, Bun,
and Deno.

```sh
npm install @masks/server
```

## Signing people in to Express

```ts
import express from "express";
import { masksExpress, requireAuth } from "@masks/server/express";

const app = express();

app.use(masksExpress({ privileges: { admin: ["catalog:admin"] } }));
app.get("/settings", requireAuth("admin"), (req, res) => res.json(req.masked));
```

1. Set `MASKS_ISSUER` to the tenant's address.
2. Set `MASKS_RESOURCE` to the app's own address.
3. Set `MASKS_SECRET` to at least 32 random characters.
4. Start the app and open `/auth`.

The first visit runs the handshake, which registers the app with masks and writes its credentials
to `masks.json`. Keep that file out of version control.

## Documentation

- [JavaScript apps](https://masks.pages.dev/reference/javascript/) covers the handshake, sessions,
  organizations, privileges, and accepting tokens.
- [Next.js](https://masks.pages.dev/reference/javascript/nextjs/),
  [Auth.js](https://masks.pages.dev/reference/javascript/authjs/), and
  [Express and Hono](https://masks.pages.dev/reference/javascript/express-and-hono/) set up each
  framework.
- [`@masks/server`](https://masks.pages.dev/reference/javascript/server/) lists every option,
  route, and method, with `Client` and `Verifier`.

MIT.
