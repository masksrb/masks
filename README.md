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
bin/setup    # postgres, database, two tenants each with their own key
bin/dev      # http://jons.auth.test:5555
```

Two tenants from the first seed, always — single-tenant assumptions do not announce themselves.

## Still ahead

Token exchange (RFC 8693) is v1.5, and three consumers need it: workflow runs, enrolled nodes, and
connectors. WebAuthn, social providers, an admin UI and a published container are v2; the previous
attempt has working implementations of the first two to draw from.

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
