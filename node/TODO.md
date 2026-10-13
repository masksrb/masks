# JavaScript SDK to-do

## The app layer

- The app layer cannot hold a DPoP-bound token. A workable shape: a `dpop: true` option makes a key for each sign-in and keeps its private JWK in the sealed session, so any process can refresh it; `client.start`, `complete`, `refresh`, and `userinfo` take that key, and the avatar route's `signedFetch` already signs with it. Still open is how an app calls its own APIs with the token, since `masked.authorization` alone no longer works, so `Masked` would need a signed `fetch`.

## Auth.js

- The proxy cannot wrap a handler of the app's own, as `auth((request) => ...)` can.
- `upstashStore` has run against serverless-redis-http, which speaks Upstash's REST API, and `redisStore` against Redis 7 through node-redis 4 and ioredis 5. It has not run against Upstash itself.
- The `signOut` server action going through `/api/auth/masks/logout` with `signOutOfIssuer` has not run in a live Next.js app. The `next-auth/react` path is tested against the Auth.js handlers.
- The issuer, resource, and credentials cannot vary per request.
- Without the proxy, `requireAuth()` returns to the page only when the page names it with `returnTo`. Next.js gives a server component no other way to learn its path.
- The live run used Next.js 16.3 and next-auth 5.0.0-beta.32 on Node 26. Other versions have not run.

## Testing

- The suite runs in CI on Node 20, 22, and 24, with Express 5, Hono 4, and Next 16. Express 4 and Workers have not run. `upstashStore` on a Worker has not run.
- Bun 1.4.3 (`bun test ./test/`, in the `oven/bun:1` image) passes 136 of 137. On Bun, an Express avatar larger than `avatarBytes` ends as an empty `200` where Node cuts the connection. The app still passes no byte past the limit.
- Deno 2.8.1 (`deno test -A test/`) passes 100 of 105 in the files it loads. The five failures use `mock.timers`, which Deno does not have. With an import map that adds `.js` to `next/server`, `next/headers`, and `next/navigation`, the 11 Next.js, Express, and Hono tests pass too. The Auth.js tests do not load, since next-auth imports `next/server` with no extension, which Deno's Node resolution refuses.
- `masksAuth`, `masksNext`, Express 5, and Hono 4 on Node have run against a live masks: the handshake, the sign-in back to the page asked for, a step-up, the avatar, and sign-out. Back-channel logout has run only against the fake issuer, since masks in Docker cannot reach the host.
