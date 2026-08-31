# masks-rails

Sign a Rails app in against a [masks](https://github.com/masksrb/masks) issuer.

One command to install, and the app is connected by somebody approving it — no
client id to copy, no secret to paste anywhere.

```ruby
# Gemfile
gem "masks-rails"
```

```
bin/rails generate masks:install
```

That mounts the engine at `/auth`, writes `config/initializers/masks.rb`, and
gitignores the file credentials land in. Set `MASKS_ISSUER`, start the app, and
open `/auth/handshake`.

## The handshake

A first-party app must not self-register anonymously — that is how a stranger's
connector also arrives. So an unconnected app is offered one button, the browser
goes to its own issuer's approval screen, and the one-time token that comes back
is redeemed server-side. **The secret never travels through the browser and
nobody types it anywhere.**

The engine writes what comes back to `config/masks.json`, mode 600. An app that
wants somewhere else says so:

```ruby
config.credentials = ->(request) { Tenant.for(request).masks_credentials }
config.store = ->(request, registration) { Tenant.for(request).connect!(registration) }
```

Those two lambdas are the whole integration for a multi-tenant app.

## Signing in

```ruby
class ThingsController < ApplicationController
  include Masks::Rails::Authentication

  before_action :authenticate_masks!

  def index
    @who = masks_identity
  end
end
```

`masks_identity`, `masks_tenant` and `masks_scopes` are what a signed-in request
carries. Tokens live in the encrypted Rails session and never reach JavaScript —
this is the backend-for-frontend pattern, and it is the default because an SPA
holding a token is an SPA where XSS lifts one.

The include is **not** blanket. `config.authenticate_everything = true` puts it
on every controller if that is what you want; otherwise include it where you
mean it.

## An SPA in front of it

`GET /auth/session` answers identity, tenant and scopes as JSON, or `401` with
somewhere to send the browser. [`@masks/client`](../web) speaks it:

```js
import { createSession } from "@masks/client"

const session = createSession()
const status = await session.status()
```

`status()` answers one of three things, and the third is why it exists:
`signed_in`, `signed_out` with where to sign in, and `handshake_required` with
where to go instead — because an app nobody has connected must not offer a
sign-in button that leads to an error page at the issuer.

## Accepting tokens

An app that is also a resource server:

```ruby
class ApiController < ApplicationController
  include Masks::Rails::ProtectedResource

  before_action { masks_protect!(scope: "things:read") }
end
```

`masks_claims` is the verified token. A refusal carries the RFC 6750 challenge
with `resource_metadata`, so a client handed nothing but a URL can find its way
to the issuer and back.

## Signing out

`DELETE /auth/logout` ends this app's session. Add `?everywhere=1` and the
response carries `logout_url` — the issuer's end-session endpoint — so signing
out can mean signing out. `config.sign_out_of_issuer = true` makes that the
default for every sign-out.

## Configuration

Every value that varies per request accepts a callable taking the request, which
is what a subdomain-per-tenant host needs.

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

## Which issuers this speaks to

masks publishes `masks_protocol_version` in its discovery document, and the
engine needs at least version 1 — the one that serves `handshake_endpoint` and
the approval flow behind it. An older issuer is refused with a sentence saying
so, rather than at the first screen anybody touches.

## License

MIT.
