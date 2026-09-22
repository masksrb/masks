<p align="center"><img src="engine/public/masks-public/icon.svg" width="120" alt="The masks rose window"></p>

# masks

A standalone, self-hostable OpenID Connect provider, with per-tenant signing keys — plus the pieces
an application needs to sign in against it.

**Documentation: [masks.pages.dev](https://masks.pages.dev)**

```
engine/    masks-server                     the OIDC provider, as a Rails engine
server/    the provider's own app           mounts the engine at /, builds the image
client/    masks                            discovery, PKCE, exchange, verification, Rails engine
web/       @masks/client                    BFF and browser PKCE, for an SPA
docs/      the site above                   Astro + Starlight
```

The provider is the `masks-server` gem. It runs as an app of its own, which is what `server/` and
the container image are, or mounted inside another Rails app with a database and secrets of its own.
Everything an application needs to sign in against it is the `masks` gem, whose Rails half loads only
when Rails does. See [Rails apps](https://masks.pages.dev/guides/rails/) for the three modes.

The server ships as a container image. Main is published as `:main` and by commit sha; a release
publishes its version, moves `:latest`, and is built for arm64 as well. It needs a Postgres, and it
migrates itself and generates its own secrets on the way up.

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
    volumes:
      - masks-storage:/rails/storage
```

See [self-hosting](https://masks.pages.dev/guides/self-hosting/) for a Postgres and a reverse
proxy.

```sh
./dev       # http://masks.localhost:12345, docs on :12346
./dev test  # all five suites, in containers
```

`./dev` needs docker and nothing else — no ruby, no node, no postgres on the host. It runs the whole
stack in the foreground: the provider, vite, the worker and the doc site, all reloading. One tenant
answers at `masks.localhost`, which is what a single-tenant deployment looks like. `./dev --multi`
declares `demo` and `acme` instead and serves them at `demo.masks.localhost:12345` — no proxy and no
`/etc/hosts`, because Rails reads the tenant off the Host header and `*.localhost` already resolves.

`./dev image` runs the production image the way it deploys, then checks that each tenant advertises
its own issuer and signs with a key of its own.

`./dev test` also needs only docker. Each suite is named for what it proves rather than for the tree
it lives in: `unit` and `integration` are the provider, `engine` and `client` are the two halves of
the gem, and `conformance` is the OpenID Foundation suite. Those five sit under `test/`, one
directory each. `web` stays with the package it tests. `./dev test client web` runs a subset; it
keeps going after a failure and names what failed.

Both OpenID Foundation certification plans pass — `oidcc-config` and `oidcc-basic`, 2213 conditions,
zero failures. `./dev test conformance` runs them.
