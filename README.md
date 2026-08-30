# masks

An auth server — a standalone, self-hostable OIDC provider — plus a client gem.

**Not yet built.** This repo holds the slot and the decisions; the code arrives when `things` needs
it, which is the point at which its shape will be known rather than guessed.

## Why it exists

`things` is simultaneously an OIDC *client* of masks (you logging in), a *resource server* for
masks-issued tokens (an agent calling the MCP endpoint), and a consumer of the client gem. So
building `things` exercises masks across its full surface, in production, continuously — which is
the ordering discipline that the previous four attempts at this lacked.

## What it is, and is not

**A standalone server, not a Rails engine.** The previous attempt shipped an engine *plus* a host
app *plus* a gem, and the engine-ness produced its worst bug: middleware and host-app controllers
fighting over `Set-Cookie`. A standalone server has no downstream app, which designs that entire
class of problem out.

The **policy DSL** from that attempt is the idea worth keeping — composable, declarative checks —
implemented against a standalone request pipeline rather than Rack middleware over a host app.

## Scope

**v1.** Tenant model with row-level security. OIDC provider: authorization code + PKCE, per-tenant
discovery, **per-tenant signing keys** (a token minted for one tenant must not verify against
another's JWKS), token, userinfo. Audience-restricted tokens (RFC 8707 `resource`). Scopes.
Actor / Client / Device / Session, all tenant-scoped. Password auth. Server-rendered login and
consent.

**Dynamic client registration, or Client ID Metadata Documents, is v1 — not v2.** Adding a custom
connector in an AI client means a client registering with no prior arrangement. Without DCR or CIMD
that flow cannot be set up at all.

**v1.5.** Token exchange (RFC 8693), so `things` can mint short-lived, narrowly-scoped credentials.
Three consumers need it — workflow runs, enrolled nodes, and connectors — which is what promotes it
from "eventually" to a real dependency.

**v2.** TOTP, WebAuthn, social providers, admin UI, docs, published gem and container.

## Standing constraints

- **masks must never be the source of the secrets required to deploy masks.** The deploy-time secret
  store stays separate; masks owns application identity only. Do not merge these later.
- **Per-tenant signing keys from the first migration.** A singleton key is not something you can
  retrofit.

## The boundary rule

**Nothing in this repo may name a host, a domain, or a secret.** Those are facts about a deployment
and belong in the private infrastructure repo that consumes this one. `bin/check-boundary` enforces
it; run it before committing.
