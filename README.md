# masks

A standalone, self-hostable OpenID Connect provider, with per-tenant signing keys — plus the pieces
an application needs to sign in against it.

**Documentation: [masks.pages.dev](https://masks.pages.dev)**

```
server/    the standalone OIDC provider     Rails, Postgres, per-tenant keys
client/    masks                            discovery, PKCE, exchange, verification, Rails engine
web/       @masks/client                    BFF and browser PKCE, for an SPA
docs/      the site above                   Astro + Starlight
```

The provider is a deployable, not a gem — it holds a database and the signing keys, and it stays
standalone. Everything an application needs to sign in against it is the one `masks` gem, whose
Rails half loads only when Rails does.

```sh
bin/setup   # dependencies, databases, two declared tenants
bin/dev     # http://jons.auth.test:5555
bin/test    # all three suites, in containers
```

`bin/test` needs docker and nothing else — no ruby, no node, no postgres on the host. It runs the
three trees above that have suites, keeps going after a failure, and names the ones that failed at
the end. `bin/test client web` runs a subset; `bin/test down` drops the cache volumes.

Both OpenID Foundation certification plans pass — `oidcc-config` and `oidcc-basic`, 2213 conditions,
zero failures. `bin/conformance` runs them.
