# masks

An auth server — a standalone, self-hostable OIDC provider — plus the two pieces an application
needs to sign in against it.

```
server/    the standalone OIDC provider          Rails, Postgres, per-tenant keys
client/    masks-client                          discovery, PKCE, exchange, verification
engine/    masks-rails                           the consumer half, mounted in a host app
```

## Why three, and why the server is not an engine

The previous attempt shipped an engine _plus_ a host app _plus_ a gem, and the engine-ness produced
its worst bug: middleware and host-app controllers fighting over `Set-Cookie`. So the **server is
standalone** — it has no downstream app, which designs that entire class of problem out.

The engine here is the other direction. It is the **consumer** side: routes, callback handling and
session wiring that mount into an application which then talks to the standalone server over HTTP.
Nothing in `engine/` issues a token; it only spends them.

`things` exercises all three at once — it is an OIDC client of the server (you logging in), a
resource server for tokens the server issued (an agent calling its MCP endpoint), and a consumer of
both gems. That is the ordering discipline the previous four attempts lacked.

## Tenancy lives here

masks is the **source of truth for tenants**. A tenant has a stable `uuid` that never changes, a
`subdomain` that addresses it, and its own signing keys. Downstream applications hold a projection
keyed by that uuid rather than defining tenants of their own.

They learn it without asking: every access token and id token carries a `tenant` claim, and the
discovery document publishes the same identity. So an application never has to call back — and never
has to forward a caller's token upstream to find out who it belongs to.

```json
"tenant": { "uuid": "45638a95-…", "subdomain": "jons", "name": "Jon's" }
```

### Per-tenant signing keys, from the first migration

A token minted for one tenant must not verify against another's JWKS. This is not something you
retrofit, so it is in migration #2, and a tenant generates its key on creation.

Isolation has three layers, and each fails differently:

| Layer | Enforced by | Fails how |
| --- | --- | --- |
| application | `TenantScoped` default scope | a forgotten scope |
| database | Postgres RLS, `FORCE` + policy | silently, if the app role is a superuser |
| signature | a per-tenant RSA key, published per-tenant JWKS | loudly — `no public key for kid` |

The third is the one worth having. Present the other tenant with a valid token and it does not read
as *forbidden*, it reads as *unintelligible*, because the key that signed it was never published
where they could find it.

## What the server implements

Authorization code with **PKCE** (S256, mandatory for public clients), refresh with rotation,
userinfo, per-tenant discovery and JWKS, password sign-in with an optional TOTP second factor, and
remembered consent.

**Dynamic client registration is v1, not v2** (RFC 7591, with 7592 read/update/delete against a
registration access token). Adding a custom connector in an AI client means a client registering with
no prior arrangement; without DCR that flow cannot be set up at all.

**Audience-restricted tokens** (RFC 8707 `resource`) are the other half of that. The `resource` a
client asks for becomes the token's `aud`, so a resource server can insist a token was minted for it
specifically rather than accepting anything the issuer signed.

### The policy DSL

The idea worth keeping from the last attempt: checks are declared, composable, and named after what
they assert, so the pipeline reads as a list rather than a method.

```ruby
class AuthorizationPolicy < Policy
  uses ClientPolicy
  checks :response_type_is_supported,
         :client_may_use_the_code_grant,
         :pkce_is_present_when_required,
         :scopes_are_permitted,
         :resources_are_absolute
end
```

`uses` runs another policy first; `checks` names methods on this one. A failure raises with an OAuth
error code and whether it is safe to hand back to the client's `redirect_uri` — which is the
distinction that keeps an open redirector from being one line away.

## Running it

```sh
brew bundle  # postgresql@17, and it must be first on PATH — see below
bin/setup    # postgres, database, two tenants each with their own key
bin/dev      # http://jons.auth.localhost:5555, plus vite on 3036
bin/ci       # rubocop, brakeman, gem audit, tests
```

The schema is dumped as **SQL**, not `schema.rb`. This is not a preference: `schema.rb` cannot
represent `CREATE POLICY` or `FORCE ROW LEVEL SECURITY`, so a database built from it has no tenant
isolation whatsoever — and `db:prepare` builds from the schema, not from migrations. That is why
`db/structure.sql` is checked in, why `bin/setup` refuses to run without a matching `pg_dump`, and
why three tests assert the policies are actually present in whatever database they find.

Two tenants from the first seed, always — single-tenant assumptions do not announce themselves.

### The login machine

The server owns the flow. `Login` runs an ordered list of states three times — `reload!`, then
`event!`, then `factor!` — and the first state to raise `PromptRequired` names the prompt the client
must show. The order of `Login::STATES` *is* the flow; nothing else encodes it.

```ruby
handles "password" do
  verify
end

prompts "second-factor" do
  touched?(:first_factor) && !touched?(:second_factor)
end
```

The client posts `{ event, ...updates }` to `/login` and gets the whole state back as JSON. Each
prompt is one Svelte component under `app/frontend/prompts`, resolved by name, so **adding a factor
is adding two files** — a state and a component — and touching the one list that orders them.

Sign-in requires JavaScript as a result; consent, account and the error pages do not.

One rule the machine has to keep: **the identifier step must never look the actor up.**
`Actor.authenticate` takes identifier and password together and burns a decoy digest when there is no
such account, and that is the only reason sign-in is not a user-enumeration oracle. A state that
branches on whether an identifier exists — a signup offer, an SSO hint — hands that oracle back.

### The container

`server/Dockerfile` builds the production image. `bin/image` builds it, runs it against the same
compose postgres on its own database, and asserts what a deploy has to get right — that the image
boots, migrates, seeds both tenants, and publishes a *different* `kid` for each.

```sh
bin/image         # build, run, and check on http://jons.auth.localhost:5556
bin/image logs
bin/image down
```

It uses `auth.localhost` rather than the `auth.test` of `bin/dev`, because `*.localhost` resolves
without touching `/etc/hosts` — so the URL it prints is one a browser can actually open.

It runs on the production environment, so it exercises the production cache and queue rather than
the development ones — which is where the last hardening bug was hiding. TLS is the only thing
relaxed: `RAILS_FORCE_SSL` and `RAILS_ASSUME_SSL` are `false` there so plain http answers locally,
and both default to `true` everywhere else.

CI builds the same image on every pull request and publishes it on `main`. Everything else arrives
through the environment; `server/.env.example` documents what, and `server/compose.yml` shows a
complete set with development-only values.

## Still ahead

Token exchange (RFC 8693) is v1.5, and three consumers need it: workflow runs, enrolled nodes, and
connectors. WebAuthn, social providers and an admin UI are v2; the previous attempt has working
implementations of the first two to draw from.

## Standing constraints

- **masks must never be the source of the secrets required to deploy masks.** The deploy-time secret
  store stays separate; masks owns application identity only. Do not merge these later.
- **Per-tenant signing keys from the first migration.** A singleton key is not something you can
  retrofit.

## The boundary rule

**Nothing in this repo may name a host, a domain, or a secret.** Those are facts about a deployment
and belong in the private infrastructure repo that consumes this one. Everything arrives through the
environment; `server/.env.example` documents what.

Run `bin/check-boundary` before committing. It is wired into CI so that the rule is greppable rather
than remembered.
