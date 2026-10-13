# Go SDK to-do

## go/web

- The avatar proxy builds its own HTTP client and Bearer header. Use the client's signing transport, so a DPoP-bound token sends a proof.
- Issuer discovery runs inside the request when the cache is stale, once per request, and again on every request after a failure. Serve the stale issuer, refresh it once in the background, and back off after a failure. Bound the issuer and verifier caches.
- Scope, Privileges, Name, and Mount cannot vary per request. Masks::Rails accepts a callable for most settings.
- Add `holds?` and `member!` equivalents to Person.

## Security

- `FileCredentials` reads its file once and keeps it. Two processes that share the file do not see each other's handshake, and one that meets `invalid_client` deletes a file the other just wrote. Read the file again when it changes.

## Testing

- Nothing has run against a live masks. Every test uses a fake issuer.
