<p align="center"><img src="engine/public/masks-public/icon.svg" width="120" alt="The masks rose window"></p>

# masks

A self-hostable OpenID Connect provider with per-tenant signing keys, and the libraries an
application uses to sign in against it.

**Documentation: [masks.pages.dev](https://masks.pages.dev)**

```
engine/    masks-server      the OIDC provider, as a Rails engine
server/    the host app      mounts the engine at /, builds the image
client/    masks             the Ruby client and its Rails engine
web/       @masks/client     the browser client, for an SPA
docs/      the site above    Astro and Starlight
test/      the suites        all but web, which keeps its own in web/test
```

The provider runs as an app of its own, which is what `server/` and the container image are, or
mounted inside another Rails app. See [Rails apps](https://masks.pages.dev/guides/rails/) for the
three modes, and [self-hosting](https://masks.pages.dev/guides/self-hosting/) for running the image
with Postgres and a reverse proxy.

```sh
docker pull ghcr.io/masksrb/masks:latest
```

Each commit on main is published as `:main` and by its sha. A release publishes its version, moves
`:latest`, and adds an arm64 build.

## Development

`./dev` needs Docker with Compose, and Ruby.

|                   |                                                                                                                                                                                               |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `./dev`           | Runs the provider, vite, the worker, and the doc site in the foreground, all reloading. One tenant answers at `http://masks.localhost:12345`, and the docs at `http://masks.localhost:12346`. |
| `./dev --multi`   | Declares the tenants `demo` and `acme`, at `http://demo.masks.localhost:12345` and `http://acme.masks.localhost:12345`. Rails reads the tenant from the `Host` header.                        |
| `./dev test`      | Runs every suite in containers, keeps going after a failure, and names what failed at the end.                                                                                                |
| `./dev test unit` | Runs one suite.                                                                                                                                                                               |
| `./dev image`     | Runs the production image and checks each tenant's issuer and keys.                                                                                                                           |
| `./dev reference` | Regenerates the reference pages.                                                                                                                                                              |

| Suite                 | Tests                                                                                                                  |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `unit`, `integration` | The provider.                                                                                                          |
| `provider`            | The engine installed into a fresh app through its generator.                                                           |
| `engine`, `client`    | The Rails engine and the plain Ruby half of the `masks` gem.                                                           |
| `web`                 | `@masks/client`.                                                                                                       |
| `conformance`         | The OpenID Foundation `oidcc-config`, `oidcc-basic`, RP-initiated logout, and back-channel logout certification plans. |
