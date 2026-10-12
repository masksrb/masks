# JavaScript SDK to-do

## The app layer

- A guarded Express or Hono request reads and seals the session two or three times, and can send two different `Set-Cookie` headers for one cookie. Keep what `masked()` resolves in a `WeakMap` keyed on the request, let `guard()` and `check()` reuse it, and remove `alreadySet`.
- `guard()` builds two Visits. Let `check()` take the Visit `guard()` already has.
- `handle()` resolves the issuer before it checks the path. Return early when `!owns(path)`, and add a public `mounted(pathname)` for `owns`, `handle`, and the Next proxy. Hono should filter the same way. The Next proxy treats the resource metadata path as a page.
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

## Security

- Store the issuer in the session and forget a session from another issuer, as go/web does. This matters when one origin serves several issuers.

## Testing

- `auth()` and `requireAuth()` have not run inside a real Next.js request.
- Only Node 26 with Express 5, Hono 4, and Next 16 has run. Express 4, Bun, Deno, and Workers have not.
- Nothing has run against a live masks. Every test uses a fake issuer.
