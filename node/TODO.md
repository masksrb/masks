# JavaScript SDK to-do

## The app layer

- `guard()` builds two Visits. Let `check()` take the Visit `guard()` already has.
- `Outcome` is a finished `Response`, so the Next adapter forces `accept: text/html` and reads `Location`. Give a refusal a kind (`login`, `step_up`, `forbidden`, `handshake`), a URL, and `toResponse(request)`.
- The avatar proxy sends a hand-built `authorization` header. Use `signedFetch`, so a DPoP-bound token sends a proof. Express buffers whole answers, so stream them with `Readable.fromWeb` and `stream.pipeline`. Replace `avatars: { bytes }` with `avatarBytes`.
- The app layer writes its own 403 challenge. Use `Verifier.challengeHeaders` and `refusal`, which now build both challenges for 401 and 403.
- `#client` builds a `Client` by hand. Use `clientFor(issuer, held)`, and make `Credentials` fit `Registration` so `registrationOf` can go.
- Move `headersWith`, `text`, `json`, and `redirect` into `app/responses.ts` and use them in avatar.ts and next.ts.
- Replace `localOr` in next.ts with `localPath(...) ?? "/"`.
- Add `Masks.from(x)` for the repeated `instanceof` checks in the adapters.
- Issuer discovery waits inside the request when stale, and forgets the issuer after a failure. Serve the stale issuer while one refresh runs, and back off after a failure.
- `memoryStore` and `memoryLogouts` never remove abandoned entries. Sweep them now and then. Bound the issuer and verifier caches.
- Run the sid and sub logout lookups at the same time, and the session store's `set` and `delete` on rotation too.
- Every sign-in start reads the registration from masks. Cache a good answer, or rely on `invalid_client`.
- Remove `Visit.flowChanged`, `Privileges.names`, and the `SessionData | undefined` branch of the refresh.
- Split masks.ts along the seams go/web uses: session and flow state, routes, and guards.
- The issuer's keys are fetched again on every request while masks is down. Back off.

## Auth.js

- The `refreshes`, `logouts`, and `replay` stores default to memory, and the guide shows an Upstash setup. Ship ready-made Redis stores, or have masks accept a refresh token again for a few seconds after it rotates.
- The Upstash example in the guide has not run against Upstash.
- `signOut()` from `next-auth/react` and the `signOut` server action do not sign out of masks. Only `/api/auth/masks/logout` with `everywhere` does.
- The issuer, resource, and credentials cannot vary per request.
- `guard()` needs the proxy to know which page to return to. Without it, a sign-in returns to `/`.
- `masksAuth` and `Masks` share the logout and scope helpers, but each still has its own handshake routes, manager check, and issuer cache. Move the connection lifecycle into one module both use.
- The live run used Next.js 16.3 and next-auth 5.0.0-beta.32 on Node 26. Other versions have not run.

## Testing

- Only Node 26 with Express 5, Hono 4, and Next 16 has run. Express 4, Bun, Deno, and Workers have not.
- `masksAuth`, `masksNext`, Express 5, and Hono 4 on Node have run against a live masks: the handshake, the sign-in back to the page asked for, a step-up, the avatar, and sign-out. Back-channel logout has run only against the fake issuer, since masks in Docker cannot reach the host.
