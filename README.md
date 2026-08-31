# masks

A standalone, self-hostable OpenID Connect provider, with per-tenant signing keys — plus the pieces
an application needs to sign in against it.

**Documentation: [masks.pages.dev](https://masks.pages.dev)**

```
server/    the standalone OIDC provider     Rails, Postgres, per-tenant keys
client/    masks-client                     discovery, PKCE, exchange, verification
engine/    masks-rails                      the consumer half, mounted in a host app
web/       @masks/client                    BFF and browser PKCE, for an SPA
docs/      the site above                   Astro + Starlight
```

```sh
bin/setup   # dependencies, databases, two declared tenants
bin/dev     # http://jons.auth.test:5555
bin/test    # all four suites, in containers
```

`bin/test` needs docker and nothing else — no ruby, no node, no postgres on the host. It runs the
four trees above that have suites, keeps going after a failure, and names the ones that failed at
the end. `bin/test engine web` runs a subset; `bin/test down` drops the cache volumes.

Both OpenID Foundation certification plans pass — `oidcc-config` and `oidcc-basic`, 2213 conditions,
zero failures. `bin/conformance` runs them.
