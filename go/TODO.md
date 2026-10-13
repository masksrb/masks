# Go SDK to-do

## go/web

- Scope, Privileges, Name, and Mount cannot vary per request. Masks::Rails accepts a callable for most settings.
- Add `holds?` and `member!` equivalents to Person.

## Security

- `FileCredentials` reads its file once and keeps it. Two processes that share the file do not see each other's handshake, and one that meets `invalid_client` deletes a file the other just wrote. Read the file again when it changes.

## Testing

- Nothing has run against a live masks. Every test uses a fake issuer.
