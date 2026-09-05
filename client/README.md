# masks

Sign a Ruby or Rails app in against a [masks](https://github.com/masksrb/masks) issuer.

```ruby
gem "masks"
```

Three parts, in one gem. **Consumers spend tokens. Resource servers accept them.** Most
client libraries only build the first, so everything above the second gets written by
hand in each resource server — its scope check, its `WWW-Authenticate` header, its
metadata document. Both halves are here, and a Rails engine that mounts them.

The engine loads only when Rails does. A Sinatra, Hanami or plain-Rack app requiring
this gem pulls in `jwt` and nothing else.

## Rails

One command to install, and the app is connected by somebody approving it — no client
id to copy, no secret to paste anywhere.

```
bin/rails generate masks:install
```

That mounts the engine at `/auth`, writes `config/initializers/masks.rb`, and gitignores
the file credentials land in. Set `MASKS_ISSUER`, start the app, and open
`/auth/handshake`.

### The handshake

A first-party app must not self-register anonymously — that is how a stranger's
connector also arrives. So an unconnected app is offered one button, the browser goes to
its own issuer's approval screen, and the one-time token that comes back is redeemed
server-side. **The secret never travels through the browser and nobody types it
anywhere.**

The engine writes what comes back to `config/masks.json`, mode 600. An app that wants
somewhere else says so:

```ruby
config.credentials = ->(request) { Tenant.for(request).masks_credentials }
config.store = ->(request, registration) { Tenant.for(request).connect!(registration) }
```

Those two lambdas are the whole integration for a multi-tenant app.

### Signing in

```ruby
class ThingsController < ApplicationController
  include Masks::Rails::Authentication

  before_action :authenticate_masks!

  def index
    @who = masks_identity
  end
end
```

`masks_identity`, `masks_tenant` and `masks_scopes` are what a signed-in request carries.
Tokens live in the encrypted Rails session and never reach JavaScript — this is the
backend-for-frontend pattern, and it is the default because an SPA holding a token is an
SPA where XSS lifts one.

The include is **not** blanket. `config.authenticate_everything = true` puts it on every
controller if that is what you want; otherwise include it where you mean it.

### An SPA in front of it

`GET /auth/session` answers identity, tenant and scopes as JSON, or `401` with somewhere
to send the browser. [`@masks/client`](../web) speaks it:

```js
import { createSession } from "@masks/client"

const session = createSession()
const status = await session.status()
```

`status()` answers one of three things, and the third is why it exists: `signed_in`,
`signed_out` with where to sign in, and `handshake_required` with where to go instead —
because an app nobody has connected must not offer a sign-in button that leads to an
error page at the issuer.

### Accepting tokens

An app that is also a resource server:

```ruby
class ApiController < ApplicationController
  include Masks::Rails::ProtectedResource

  before_action { masks_protect!(scope: "things:read") }
end
```

`masks_claims` is the verified token. A refusal carries the RFC 6750 challenge with
`resource_metadata`, so a client handed nothing but a URL can find its way to the issuer
and back.

### Avatars

Every actor has three faces at once — an uploaded `photo`, an `identicon`, and two-letter
`initials`. All three arrive on the id token, so drawing one costs no request.

```erb
<img src="<%= masks_claims.avatars.identicon %>?size=64" width="64" height="64" alt="">
```

A photo is a likeness of a person and needs a token, which an `<img>` cannot carry, so the engine
proxies it with the token this app already holds:

```erb
<img src="/auth/avatar" width="64" height="64" alt="">
```

`masks_claims.picture` resolves the standard OIDC claim — an offsite `picture_url` if the actor set
one, then the photo, then the identicon. `issuer.avatar_url(sub, style:, size:)` builds a URL for a
subject this app holds no token for. Sizes are 32, 64, 128, 256 or 512.

### Signing out

`DELETE /auth/logout` ends this app's session. Add `?everywhere=1` and the response
carries `logout_url` — the issuer's end-session endpoint — so signing out can mean
signing out. `config.sign_out_of_issuer = true` makes that the default for every
sign-out.

### Configuration

Every value that varies per request accepts a callable taking the request, which is what
a subdomain-per-tenant host needs.

| | |
|---|---|
| `issuer` | the masks issuer this app signs in against |
| `resource` | this app's own identifier, when it also accepts tokens |
| `resource_scopes` | what it accepts, published in its RFC 9728 metadata |
| `scope` | what to ask the issuer for; defaults to `openid profile email` |
| `credentials` / `store` | where the handshake's result lives |
| `credentials_path` | where the default store writes; `config/masks.json` |
| `after_sign_in` / `after_sign_out` | paths on this host |
| `parent_controller` | what the engine's pages inherit, for your layout |
| `authenticate_everything` | include `Authentication` on every controller |
| `sign_out_of_issuer` | make every sign-out an RP-initiated logout |
| `session_key` | the session key the tokens live under |

## Any Ruby app

Everything above is `Masks::Client` underneath, and it is usable directly — the engine
holds no protocol of its own.

### The consumer half

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

`start` sends a nonce only when `openid` was asked for, so holding one means an id token
is owed — which is what lets the check on the way back be exact rather than vacuously
true.

Also: `refresh`, `exchange`, `revoke`, `introspect`, `userinfo`, and `end_session_url`.

Discovery and JWKS are cached for five minutes, with invalidate-and-refetch on an unknown
`kid`, so a key rotation is picked up without a restart. The cache is real only if the
`Issuer` is: use `Masks::Client::Issuer.resolve`, or the registry behind it, rather than
constructing one per request.

### The handshake

The flow that connects a first-party app, rather than two helpers and sixty lines of
state in every consumer:

```ruby
handshake = Masks::Client::Handshake.new(
  issuer, name: "things", resource: "https://app.example.com/mcp",
  redirect_uris: [ "https://app.example.com/auth/callback" ],
  return_to: "https://app.example.com/"
)

started = handshake.start          # hold started[:state]; send the browser on
registration = handshake.complete(params, state: held)
```

`complete` refuses an `error`, a `state` that does not match this browser, and an `iss`
that is not the issuer it asked — each **before** anything is redeemed.

### The resource-server half

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

`authenticate` answers `Claims` or raises. A refusal builds the RFC 6750 challenge
carrying `resource_metadata` and the scopes it would have accepted:

```ruby
response.headers["WWW-Authenticate"] = resource.challenge(error)
```

`resource.metadata` is the RFC 9728 document to serve at
`/.well-known/oauth-protected-resource`. The `scope_descriptions` extension in it is how
an auth server renders your scopes as sentences on its consent screen — it has no other
way to know what `things:read` means.

There is a Rack middleware for consumers that want the challenge below the framework:

```ruby
use Masks::Client::Rack, resource: resource, scope: "things:read"
```

### Introspection

A resource server doing JWT-only validation cannot see a revocation until the token
expires. Asking is the honest answer:

```ruby
found = session.introspect(token)
found.active? && found.permits?("things:read")
```

`Introspection` is a `Claims` whose `permit!` raises when the issuer says the token is
not active, so switching from local verification to asking does not mean remembering to
check a boolean.

## Which issuers this speaks to

masks publishes `masks_protocol_version` in its discovery document, and this gem needs at
least version 1 — the one that serves `handshake_endpoint` and the approval flow behind
it. An older issuer is refused with a sentence saying so, rather than at the first screen
anybody touches.

## License

MIT.
