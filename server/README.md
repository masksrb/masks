# masks server

The standalone OpenID Connect provider. Rails 8, Postgres, one RS256 signing key per tenant.

This is a deployable rather than a library. It holds a database and the signing keys, and it owns
its own routes, session and cookie — there is no host application. An app that wants to *sign in
against* it takes the [`masks` gem](../client) instead.

**Documentation: [masks.pages.dev](https://masks.pages.dev)**

```sh
bin/setup   # dependencies, database, two declared tenants
bin/dev     # http://demo.auth.test:5555
```

Run these from the repository root, not from here.

## What it is

`config.load_defaults 8.1`, with no Active Storage, no Action Cable and no Action Text.

| | |
| --- | --- |
| tenancy | every table carries `tenant_id`, under `FORCE ROW LEVEL SECURITY` |
| keys | one RSA keypair per tenant, published only at that tenant's JWKS endpoint |
| sign-in | eleven ordered `LoginState`s; the order is the flow |
| admin | `/manage`, a GraphQL API behind `masks:manage` |
| conformance | both OpenID Foundation plans pass — 2213 conditions, zero failures |

## Layout

```
app/models/          Tenant, Actor, Client, Token and its nine subclasses
app/logins/          the login machine — one file per state
app/policies/        declarative checks, named after what they assert
app/graphql/manage/  the administration API
app/frontend/        Svelte, for the prompts and the console
db/                  structure.sql, because schema.rb cannot represent a policy
```

## Configuration

Everything that names a host, a port or a credential arrives through the environment.
`.env.example` documents the full set, and `bin/setup` copies it to `.env`.

The four that matter most:

| | |
| --- | --- |
| `MASKS_TENANTS` | comma or space separated, ensured on boot |
| `MASKS_TENANT` | pin the installation to one tenant, reached at every hostname |
| `MASKS_PUBLIC_ORIGIN_TEMPLATE` | the origin this installation is reached at; **required outside development** |
| `ENCRYPTION_*` | replace before storing anything real — `bin/rails db:encryption:init` |

Full list at [Configuration](https://masks.pages.dev/reference/configuration/).

## The database role must not be a superuser

A superuser bypasses row-level security unconditionally, and a table's owner bypasses it unless the
table is `FORCE`d. Either makes every isolation test pass without proving anything.
`db/docker-entrypoint-initdb.d` creates a separate non-superuser role rather than letting Rails
connect as `POSTGRES_USER`.

## Tests

```sh
bin/test server      # in containers, from the repository root
bin/rails test       # on the host, if you have the toolchain
```

Isolation is asserted directly in `test/models/tenant_isolation_test.rb` and
`test/models/row_level_security_test.rb`. Enumeration resistance is asserted in
`test/models/login_enumeration_test.rb`.

Rate limiting runs on `Rails.cache`, and the real store is configured in development and test as
well as production — a `:null_store` would make every limit a silent no-op exactly where you would
try to verify it.

## Before committing

```sh
bin/check-boundary
```

Nothing in the repository may name a host, a domain or a secret. It runs in CI too.
