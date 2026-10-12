# Go SDK to-do

## go/web

- Require and Either load the session again after Session already loaded it, so a guarded request unseals twice and can write the cookie twice. Reuse the state Session puts in the context, and add one `visit(w, r)` helper for the site-then-load start of each handler.
- go/web builds its own challenges in guard.go. Use `masks.Verifier.Challenge`, `ProofAlgorithms`, and `ResourceMetadataURL` and delete the copies.
- The manage check is written four times in flows.go. Make one `mayManage(w, r, s, held) bool`.
- `site()` and `verifier()` each resolve the resource, and only `site()` requires https. Share one `resourceFor(r)` that requires https.
- The avatar proxy builds its own HTTP client and Bearer header. Use the client's signing transport, so a DPoP-bound token sends a proof.
- `site.client` builds a `masks.Client` by hand. Use `s.issuer.Client(s.held.Registration(), nil, nil)`.
- Issuer discovery runs inside the request when the cache is stale, once per request, and again on every request after a failure. Serve the stale issuer, refresh it once in the background, and back off after a failure. Bound the issuer and verifier caches.
- `start` resolves the site twice to check the registration. Split out `registered(ctx, s)`.
- Back-channel logout should pick one key, sid if present and sub otherwise, and make one `Depart` call.
- Share one scope-merge helper between `scopeFor` and `approvedScope`, and add `callbackURI` and `delegationURI` helpers.
- Remove `Person.Expiry()` and `App.MetadataPath`, which nothing calls.
- Scope, Privileges, Name, and Mount cannot vary per request. Masks::Rails accepts a callable for most settings.
- Add `holds?` and `member!` equivalents to Person.

## Security

- Back-channel logout does not refuse a logout token whose jti it has seen before.
- With `IssuerFor` and the default `FileCredentials("masks.json")`, every issuer shares one client secret. Key the file by issuer, or refuse that configuration.

## Testing

- Nothing has run against a live masks. Every test uses a fake issuer.
