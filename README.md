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

The provider is a deployable rather than a gem: it holds a database and the signing keys, and it
stays standalone. Everything an application needs to sign in against it is the one `masks` gem,
whose Rails half loads only when Rails does.

The server ships as a container image. Main is published as `:main` and by commit sha; a release
publishes its version, moves `:latest`, and is built for arm64 as well. It needs a Postgres and
four secrets, and it migrates itself on the way up.

```sh
docker pull ghcr.io/masksrb/masks:latest
```

```yml
services:
  masks:
    image: ghcr.io/masksrb/masks:latest
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_USER: masks
      POSTGRES_PASSWORD: ...
      POSTGRES_DATABASE: masks
      MASKS_TENANTS: acme
      MASKS_PUBLIC_ORIGIN_TEMPLATE: https://%{subdomain}.auth.example.com
      SECRET_KEY_BASE: ...
      ENCRYPTION_PRIMARY_KEY: ...
      ENCRYPTION_DETERMINISTIC_KEY: ...
      ENCRYPTION_KEY_DERIVATION_SALT: ...
```

`deploy/roles/masks` is the same thing as an Ansible role, behind a reverse proxy.

```sh
./dev       # http://masks.localhost:12345, docs on :12346
bin/test    # all three suites, in containers
```

`./dev` needs docker and nothing else — no ruby, no node, no postgres on the host. It runs the whole
stack in the foreground: the provider, vite, the worker and the doc site, all reloading. One tenant
answers at `masks.localhost`, which is what a single-tenant deployment looks like. `./dev --multi`
declares `demo` and `acme` instead and serves them at `demo.masks.localhost:12345` — no proxy and no
`/etc/hosts`, because Rails reads the tenant off the Host header and `*.localhost` already resolves.

`./dev image` runs the production image the way it deploys, then checks that each tenant advertises
its own issuer and signs with a key of its own.

`bin/test` also needs only docker. It runs the three trees above that have suites, keeps going after
a failure, and names the ones that failed at the end. `bin/test client web` runs a subset;
`bin/test down` drops the cache volumes.

Both OpenID Foundation certification plans pass — `oidcc-config` and `oidcc-basic`, 2213 conditions,
zero failures. `bin/conformance` runs them.
