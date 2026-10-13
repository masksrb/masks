<p align="center"><img src="https://raw.githubusercontent.com/masksrb/masks/main/engine/public/masks-public/icon.svg" width="120" alt="The masks rose window"></p>

# masks

Sign a Ruby or Rails app in against a [masks](https://github.com/masksrb/masks) issuer.

```ruby
gem "masks"
```

The gem signs people in to an app, and accepts the tokens masks issues when the app is also a
resource server. Its Rails engine loads only when Rails does, so a Sinatra, Hanami, or plain Rack
app pulls in `jwt` and nothing else. See
[Connecting via SDK](https://masks.pages.dev/guides/connecting-via-sdk/) for what it covers beside
the browser package.

## Rails

```sh
bin/rails generate masks:install --resource https://app.example.com
```

That mounts the engine at `/auth`, writes `config/initializers/masks.rb`, and gitignores
the file credentials land in. Set `MASKS_ISSUER`, start the app, and open
`/auth/handshake`. [Rails apps](https://masks.pages.dev/reference/ruby/) walks through the rest.

### The handshake

An app connects to its issuer by somebody approving it. An unconnected app sends the browser to
the issuer's approval screen, and the server redeems the one-time token that comes back, so the
client secret never passes through the browser. The handshake registers the app for
`config.resource`, an absolute URL on the app's own origin, and refuses without one. A connected app
asks before it rotates, because reconnecting takes it offline for a moment.

Once an app is connected, only somebody `config.manages` approves can reconnect or disconnect it.
It names a [privilege](#privileges), or is a callable taking the request, or the request and
`masked`. The engine refuses everyone when it is unset:

```ruby
config.manages = :admin
config.manages = ->(request, masked) { masked.subject == ENV["OWNER_SUB"] }
```

The engine writes what comes back to `config/masks.json`, mode 600. A multi-tenant app keeps it
somewhere else with two callables:

```ruby
config.credentials = ->(request) { Tenant.for(request).masks_credentials }
config.store = ->(request, registration) { Tenant.for(request).connect!(registration) }
```

### Signing in

```ruby
class DashboardController < ApplicationController
  include Masks::Rails::Authentication

  masked!

  def index
    @who = masked.name
  end
end
```

`masked` is everything about the signed-in request in one object: `subject`, `name`, `nickname`,
`email`, `picture`, `avatars`, `tenant`, `organization`, `organizations`, `role?`, `scopes`,
`privileges`, `privilege?`, `access_token`, and `signed_in?`, with `masked["claim"]` for any other
claim. In a view it is the same helper. Tokens live in the encrypted Rails session and never reach
JavaScript.

### Privileges

A privilege names what an action needs: scopes the person holds in masks, a role in the organization
they signed in to, or both. A list is shorthand for `{ scope: [...] }`.

```ruby
Masks::Rails.configure do |config|
  config.privileges = {
    admin: %w[catalog:admin],
    billing: { role: %w[owner billing] },
    acme_admin: { scope: %w[catalog:admin], role: "owner", organization: "acme" }
  }
end

class SettingsController < ApplicationController
  masked!
  masked! :admin, only: %i[create update destroy]
end
```

`masked!` with no privilege needs only a sign-in. A privilege's scopes stay out of every ordinary
sign-in. When a signed-in person lacks one, the browser goes through masks once to ask for it and
comes back, and the action answers `403` when masks does not grant it. A missing role or organization
answers `403` at once. `masked.privilege?(:admin)` and `masked.privileges` tell a view what the sign-in
holds, and `/auth/session` answers `privileges`. See
[privileges](https://masks.pages.dev/reference/ruby/#privileges).

`config.authenticate_everything = true` includes `Authentication` on every controller. Otherwise
include it where it applies.

### A single-page app in front of it

`GET /auth/session` answers identity, tenant, and scopes as JSON, or `401` with where to send the
browser. [`@masks/client`](https://masks.pages.dev/reference/javascript/client/) reads it:

```js
import { createSession } from "@masks/client"

const session = createSession()
const status = await session.status()
```

`status()` answers `signed_in`, `signed_out` with where to sign in, or `handshake_required` with
where to connect the app first.

### Accepting tokens

An app that is also a resource server:

```ruby
class ApiController < ApplicationController
  include Masks::Rails::ProtectedResource

  masked! :read, except: :metadata

  def metadata
    render json: masks_resource_metadata
  end
end
```

`masked!` checks a [privilege](#privileges) against the bearer token, here
`config.privileges = { read: %w[xixo:catalog:read] }`. `masked` reads the verified token. A refusal carries the RFC 6750 challenge with
`resource_metadata`, which points a client at `/.well-known/oauth-protected-resource`. The engine
does not route that path, so route it to an action like `metadata` above. A DPoP-bound token is
accepted only with a valid proof, as in [Masks::Client::Resource](#the-resource-server-half).

### Organizations

A person signs in to an app as a member of one organization when the app asks for the
`organization` scope. Someone in several organizations picks one, and an app can pick for them by
naming it, with `/auth?organization=acme` or with `config.organization` for every sign-in.

```ruby
Masks::Rails.configure do |config|
  config.scope = %w[openid profile email offline_access organization]
  config.organization = ->(request) { request.subdomain }
end

class BillingController < ApplicationController
  include Masks::Rails::Authentication

  masked! :billing
end
```

`masked.organization` is the organization signed in to (its `id`, `key`, `name`, and `role`), or
`nil`, and `masked.role?("owner")` asks about the role held in it. A refresh reads the person's
profile again, so a promotion or demotion reaches the app within an access token's lifetime.
`/auth/session` answers the same thing as `organization`.

`masked.organizations` lists every organization the person has joined, each with the role held in
it, and `/auth/session` answers it as `organizations`. Switching sends the person through sign-in
again naming the other one, which asks nothing more when they are already a member:

```erb
<% masked.organizations.each do |held| %>
  <%= link_to held.name, masks_login_url(organization: held.key, return_to: request.path) %>
<% end %>
```

A privilege with a role refuses with 403, as `insufficient_organization` when the person signed in
to none and `insufficient_role` when they hold another role. A resource server asks the same of a
token with `masked!`.

Naming an organization without asking for the scope still holds the sign-in to its members and its
sign-in policy, and the app learns nothing about the role.

### Avatars

Every account has three avatars: an uploaded `photo`, an `identicon`, and two-letter `initials`.
All three arrive on the ID token.

```erb
<img src="<%= masked.avatars.identicon %>?size=64" width="64" height="64" alt="">
```

A photo needs a token, which an `<img>` cannot carry, so the engine proxies it with the token the
app holds:

```erb
<img src="/auth/avatar" width="64" height="64" alt="">
```

`masked.picture` is the standard OIDC `picture` claim when the account set one, then the photo,
then the identicon. `issuer.avatar_url(sub, style:, size:)` builds a URL for a subject this app holds
no token for. Sizes are 32, 64, 128, 256, or 512.

### Signing out

`DELETE /auth/logout` ends this app's session and revokes its refresh token at the issuer. With `?everywhere=1` the response also carries
`logout_url`, the issuer's end-session endpoint. `config.sign_out_of_issuer = true` makes that the
default for every sign-out.

### Configuration

Every value that varies per request accepts a callable taking the request, which is what
a subdomain-per-tenant host needs.

| | |
|---|---|
| `issuer` | the masks issuer this app signs in against |
| `resource` | this app's own identifier, which the handshake registers and tokens name as their audience |
| `resource_scopes` | what it accepts, published in its RFC 9728 metadata |
| `scope` | what to ask the issuer for, `openid profile email` by default |
| `privileges` | named scopes, roles, and organizations that `masked!` checks, none by default |
| `organization` | the organization every sign-in names, by key |
| `credentials` / `store` | where the handshake's result lives |
| `manages` | who may reconnect or disconnect a connected app |
| `credentials_path` | where the default store writes, `config/masks.json` by default |
| `after_sign_in` / `after_sign_out` | paths on this host |
| `parent_controller` | what the engine's pages inherit, for your layout |
| `authenticate_everything` | include `Authentication` on every controller |
| `sign_out_of_issuer` | make every sign-out an RP-initiated logout |
| `session_key` | the session key the tokens live under |
| `delegates` / `delegation_redirect_uri` | ask for delegation in the handshake, and where connecting an account returns |
| `replay` | where seen DPoP proofs are remembered, any object with `first?(key, expires_in:)`, this process's memory by default |

## Any Ruby app

The Rails engine is built on `Masks::Client`, which any Ruby app can use directly.

### The consumer half

```ruby
session = Masks::Client::Session.new(
  issuer: "https://demo.auth.example.com",
  client_id: id, client_secret: secret,
  redirect_uri: "https://app.example.com/auth/callback"
)

started = session.start(resource: "https://app.example.com/mcp")

tokens = session.complete(code: params[:code], verifier: held[:verifier])
identity = session.identity(tokens)
```

Hold `started[:state]`, `started[:nonce]`, and `started[:verifier]` in the session, and send the
browser to `started[:url]`. `start` sends a nonce only when the scope includes `openid`. Check the
returned `state` yourself, and compare `identity["nonce"]` with the one you held.

`Session` also has `refresh`, `exchange`, `client_credentials`, `device_authorization`,
`await_device`, `enroll`, `unenroll`, `revoke`, `introspect`, `userinfo`, `end_session_url`, and
`transport`. It authenticates with `client_secret`, or with `private_key` and `key_id` for
`private_key_jwt`. A `Masks::Client::Key` passed as `private_key` names itself by its thumbprint, so
`key_id` can be left out.

`userinfo` takes `Tokens` or an access token string. A string and a `Bearer` token go as `Bearer`.
A DPoP-bound token goes as `Authorization: DPoP` with a proof from the session's `dpop:` key, and
raises `Masks::Client::Error` when the session holds no key.

An app that has claimed a namespace enrolls a machine with `enroll`. It returns an
`Enrollment` whose `initial_access_token` the machine spends once to register its own public key.

```ruby
enrollment = session.enroll(scope: "xixo:agent", name: "nas", expires_in: 900)
enrollment.initial_access_token
```

`unenroll` takes the machine's client ID. masks archives the machine and revokes its tokens, and
refuses a client the app did not enroll.

```ruby
session.unenroll(machine_client_id)
```

### A machine

A machine enrolled by an app makes two P-256 keys: one to sign its client assertions, and one to
hold its tokens with DPoP. It registers the public half of the first with the app's initial access
token, and keeps both private halves to itself.

```ruby
key = Masks::Client::Key.generate
dpop = Masks::Client::Key.generate

registration = Masks::Client::Registration.create(
  "https://demo.auth.example.com", token: initial_access_token,
  name: "nas", jwks: key, token_endpoint_auth_method: "private_key_jwt",
  grant_types: [ "client_credentials" ], dpop_bound_access_tokens: true
)

File.write("machine.json", { "client_id" => registration.client_id, "key" => key.to_h,
                             "dpop" => dpop.to_h }.to_json, perm: 0o600)

session = registration.session(private_key: key, dpop: dpop)
tokens = session.client_credentials(scope: "xixo:agent")
tokens.bound?
```

`Registration.create` sends `grant_types` and `response_types` only when they are given, and masks
fills in the rest: an enrolled machine gets `client_credentials`, and an open registration gets
`authorization_code` and `code`. `jwks:` takes a `Key`, a list of them, or a JWK Set. `Key#jwks` and `Key#public_jwk` hold only the
public half, and `Key#to_h` holds the private one. `Key.parse` reads a key back from that hash, its
JSON, or a PEM. A key on another curve, or a public key, raises `ArgumentError`.

`Registration.create` with a `token:` posts to `/register` even when discovery publishes no
`registration_endpoint`, because a tenant that turns open registration off still redeems initial
access tokens there. `read`, `update`, and `delete` raise `Masks::Client::Foreign` when the
`registration_client_uri` names an origin other than the issuer's, and send nothing.

A `Session` given `dpop:` sends a new DPoP proof with every request to the token endpoint:
`complete`, `client_credentials`, `refresh`, `exchange`, and `await_device`. A server that answers
`use_dpop_nonce` with a `DPoP-Nonce` header gets one retry carrying that nonce, and the nonce is
kept for that origin's next request. A token endpoint that answers a proven request with a `Bearer`
token is refused with `invalid_dpop_proof`. Revocation, introspection, enrollment, and device
authorization are sent without a proof.

`transport` sends requests to a resource with those tokens. It takes the origins it may send them to
and raises `Masks::Client::Foreign` for any other URL before it fetches a token. An origin in plain
`http` follows the same rule as the issuer, and raises `Masks::Client::Insecure` when the transport
is built. A resource's answers are not limited to 1 MB.

```ruby
api = session.transport("https://app.example.com", scope: "xixo:agent")

response = api.get("https://app.example.com/mcp/feeds?page=2")
api.post("https://app.example.com/mcp/feeds", body: { "name" => "notes" })
```

Each request carries `Authorization: DPoP` and a proof naming the method, the URL without its query,
and the token's hash in `ath`. A resource that answers `401` with `use_dpop_nonce` in
`WWW-Authenticate` and a new `DPoP-Nonce` is asked once more. The answer is a `Net::HTTPResponse`,
which the transport returns whatever its status. A `Bearer` token goes as `Bearer` with no proof.

Without `tokens:`, the transport asks for `client_credentials` with the `scope` and `resource` it was
given, and again when they expire. With `tokens:`, it renews them with their refresh token, keeps that
refresh token when the server does not rotate it, and yields the new tokens so they can be stored:

```ruby
api = session.transport("https://app.example.com", tokens: held) { |tokens| store(tokens.to_h) }
```

`Masks::Client::Transport.new(*origins, tokens:, key:)` builds one around tokens you already hold.

### The device flow

A device with no browser asks for a code, shows it, and polls until somebody approves it:

```ruby
device = session.device_authorization(scope: %w[openid offline_access], resource: "https://app.example.com/mcp")

puts "Open #{device.verification_uri} and enter #{device.user_code}"

tokens = session.await_device(device)
```

`await_device` waits `interval` seconds between polls, five when the server names none, and five
seconds longer after each `slow_down`. It keeps polling through `authorization_pending`. It raises
`Masks::Client::Rejected` with the server's code for `access_denied`, `expired_token`, or any other
refusal, and raises `expired_token` without polling once `device.expires_at` has passed. A session
holding a DPoP key proves each poll, and the tokens it returns are held to that key.

Discovery and JWKS are cached for five minutes and refetched on an unknown `kid`, so a key rotation
needs no restart. The cache lives on the `Issuer`, so use `Masks::Client::Issuer.resolve` instead
of constructing one per request.

Every request the gem makes goes over `https`, or plain `http` to `localhost`, a `*.localhost`
name, or a loopback address. Any other `http` URL raises `Masks::Client::Insecure` before anything is
sent. A deployment that reaches its issuer over a private network in plain `http` sets
`Masks::Client.plain_http = true`. Answers from the issuer are read up to 1 MB, and an answer that
is not a JSON object raises `Masks::Client::Rejected` with the code `invalid_response`.

### The handshake

The flow that connects a first-party app:

```ruby
handshake = Masks::Client::Handshake.new(
  issuer, name: "xixo", resource: "https://app.example.com/mcp",
  redirect_uris: [ "https://app.example.com/auth/callback" ],
  return_to: "https://app.example.com/"
)

started = handshake.start
registration = handshake.complete(params, state: held)
```

Hold `started[:state]` and send the browser to `started[:url]`. Before it redeems anything,
`complete` refuses an `error`, a `state` that does not match this browser, and an `iss` other than
the issuer it asked.

### The resource-server half

```ruby
resource = Masks::Client::Resource.new(
  issuer: "https://demo.auth.example.com",
  url: "https://app.example.com/mcp",
  scopes: { "xixo:catalog:read" => "Search your catalog" }
)

claims = resource.authenticate(
  request.authorization, scope: "xixo:catalog:read",
  proof: request.get_header("HTTP_DPOP"), method: request.request_method, url: request.url
)
claims.subject
claims.tenant.subdomain
```

`authenticate` answers `Claims` or raises. A token bound to a key with DPoP carries `cnf.jkt`, and is
accepted only as `Authorization: DPoP` with a proof signed by that key for this method, URL, and
token, made within the last minute and never seen before. `proof`, `method`, and `url` are what it
checks the proof against. Seen proofs are kept in the process's memory. A deployment with several
processes passes `replay:` to `Resource.new`, or sets `config.replay` in a Rails app, to any object
whose `first?(key, expires_in:)` answers true only once for each key across every process.

When that store raises, `authenticate` raises `Masks::Client::ReplayUnavailable`, which is not a
challenge. The Rack middleware and a Rails controller answer `503` with `temporarily_unavailable`
and no `WWW-Authenticate` header, so a client keeps a token that is still good. A proof the store
has already seen is still refused with `401`.

A refusal builds the RFC 6750 challenge carrying `resource_metadata` and the scopes it would have
accepted:

```ruby
response.headers["WWW-Authenticate"] = resource.challenge(error)
```

`resource.metadata` is the RFC 9728 document to serve at `/.well-known/oauth-protected-resource`.
Its `scope_descriptions` extension gives masks the sentences its consent screen shows for each
scope.

A Rack middleware does the same below the framework, proof included:

```ruby
use Masks::Client::Rack, resource: resource, scope: "xixo:catalog:read"
```

### Introspection

A resource server that only verifies the JWT sees a revocation when the token expires. Introspection
asks the issuer:

```ruby
found = session.introspect(token)
found.active? && found.permits?("xixo:catalog:read")
```

`Introspection` is a `Claims` whose `permit!` also raises when the token is not active.

### Somebody else's account

An app that acts as somebody at Google, Microsoft, or an MCP server while they are away asks masks for
a [delegation](https://masks.pages.dev/guides/connecting-via-sdk/#delegation). masks keeps and refreshes the
provider's tokens. The app keeps one secret per connection and trades it for a live access token when
the last one runs out.

```ruby
delegations = Masks::Client.delegations(
  ENV["MASKS_ISSUER"], client_id: id, client_secret: secret, redirect_uri: "https://app.test/connect/callback"
)

started = delegations.start(provider: "google")
session[:connecting] = started
redirect_to started["url"]

held = delegations.finish(params: params, started: session.delete(:connecting))
held.connection
held.secret

upstream = delegations.token(held.secret, connection: held.connection)
upstream.access_token
upstream.expires_at
upstream.secret
```

A Rails app sets `config.delegates = true`, so its handshake asks for `masks:delegate:` and the token
exchange with it.

`upstream.secret` replaces the one you passed in, every time. `Delegations::Refused` means somebody
has to connect again, and `Delegations::Unavailable` is worth retrying. Both carry `secret` when masks
had already rotated it, so keep it. Spend a secret from one place at a time, because spending one
twice revokes it.

Tests use the fake, which needs no issuer:

```ruby
require "masks/client/delegations/fake"

fake = Masks::Client::Delegations::Fake.new
started = fake.start(provider: "notion")
held = fake.finish(params: fake.approve(started), started: started)

fake.token(held.secret, connection: held.connection)
fake.revoke(held.connection)
fake.unavailable(held.connection)
```

## Documentation

The full reference is generated from this gem at [masks.pages.dev](https://masks.pages.dev): `ruby`
for `Masks::Client` and `rails` for the engine.

## License

MIT.
