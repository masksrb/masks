# masks-client

An OIDC client for [masks](https://github.com/masksrb/masks), in two halves.

**Consumers spend tokens. Resource servers accept them.** Most client libraries
only build the first, so everything above the second gets written by hand in
each resource server — its scope check, its `WWW-Authenticate` header, its
metadata document. Both halves are here.

```ruby
gem "masks-client"
```

A Rails app wants [`masks-rails`](../engine) instead, which mounts this.

## The consumer half

```ruby
session = Masks::Client::Session.new(
  issuer: "https://jons.auth.example.com",
  client_id: id, client_secret: secret,
  redirect_uri: "https://app.example.com/auth/callback"
)

started = session.start(resource: "https://app.example.com/mcp")
# hold started[:state], started[:nonce] and started[:verifier]; send the
# browser to started[:url]

tokens = session.complete(code: params[:code], verifier: held[:verifier])
identity = session.identity(tokens)
```

`start` sends a nonce only when `openid` was asked for, so holding one means an
id token is owed — which is what lets the check on the way back be exact
rather than vacuously true.

Also: `refresh`, `exchange`, `revoke`, `introspect`, `userinfo`, and
`end_session_url`.

Discovery and JWKS are cached for five minutes, with invalidate-and-refetch on
an unknown `kid`, so a key rotation is picked up without a restart. The cache is
real only if the `Issuer` is: use `Masks::Client::Issuer.resolve`, or the
registry behind it, rather than constructing one per request.

## The handshake

The flow that connects a first-party app, rather than two helpers and sixty
lines of state in every consumer:

```ruby
handshake = Masks::Client::Handshake.new(
  issuer, name: "things", resource: "https://app.example.com/mcp",
  redirect_uris: [ "https://app.example.com/auth/callback" ],
  return_to: "https://app.example.com/"
)

started = handshake.start          # hold started[:state]; send the browser on
registration = handshake.complete(params, state: held)
```

`complete` refuses an `error`, a `state` that does not match this browser, and
an `iss` that is not the issuer it asked — each **before** anything is redeemed.

## The resource-server half

```ruby
resource = Masks::Client::Resource.new(
  issuer: "https://jons.auth.example.com",
  url: "https://app.example.com/mcp",
  scopes: { "things:read" => "Search your catalog" }
)

claims = resource.authenticate(request.authorization, scope: "things:read")
claims.subject
claims.tenant.subdomain
```

`authenticate` answers `Claims` or raises. A refusal builds the RFC 6750
challenge carrying `resource_metadata` and the scopes it would have accepted:

```ruby
response.headers["WWW-Authenticate"] = resource.challenge(error)
```

`resource.metadata` is the RFC 9728 document to serve at
`/.well-known/oauth-protected-resource`. The `scope_descriptions` extension in
it is how an auth server renders your scopes as sentences on its consent
screen — it has no other way to know what `things:read` means.

There is a Rack middleware for consumers that want the challenge below the
framework:

```ruby
use Masks::Client::Rack, resource: resource, scope: "things:read"
```

## Introspection

A resource server doing JWT-only validation cannot see a revocation until the
token expires. Asking is the honest answer:

```ruby
found = session.introspect(token)
found.active? && found.permits?("things:read")
```

`Introspection` is a `Claims` whose `permit!` raises when the issuer says the
token is not active, so switching from local verification to asking does not
mean remembering to check a boolean.

## License

MIT.
