# JavaScript SDK to-do

## The app layer

- The app layer cannot hold a DPoP-bound token. The avatar route sends its token through `signedFetch`, so it needs only the key once a session can hold one.

## Auth.js

- The proxy cannot wrap a handler of the app's own, as `auth((request) => ...)` can.
- `upstashStore` has run against serverless-redis-http, which speaks Upstash's REST API, and `redisStore` against Redis 7 through node-redis 4 and ioredis 5. It has not run against Upstash itself.
- `signOut()` from `next-auth/react` and the `signOut` server action do not sign out of masks. Only `/api/auth/masks/logout` with `everywhere` does.
- The issuer, resource, and credentials cannot vary per request.
- `requireAuth()` needs the proxy to know which page to return to. Without it, a sign-in returns to `/`.
- `masksAuth` and `Masks` share the handshake routes through `Handshakes`, but each keeps its own manager check, and only `Masks` checks at sign-in that masks still knows the app.
- The live run used Next.js 16.3 and next-auth 5.0.0-beta.32 on Node 26. Other versions have not run.

## Testing

- Only Node 26 with Express 5, Hono 4, and Next 16 has run. Express 4, Bun, Deno, and Workers have not. `upstashStore` on a Worker has not run.
- `masksAuth`, `masksNext`, Express 5, and Hono 4 on Node have run against a live masks: the handshake, the sign-in back to the page asked for, a step-up, the avatar, and sign-out. Back-channel logout has run only against the fake issuer, since masks in Docker cannot reach the host.
