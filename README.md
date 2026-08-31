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
```

Both OpenID Foundation certification plans pass — `oidcc-config` and `oidcc-basic`, 2213 conditions,
zero failures. `bin/conformance` runs them.
