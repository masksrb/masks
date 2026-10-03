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
test/      the suites        one directory each
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

`./dev` needs Docker and nothing else.

```sh
./dev            # http://masks.localhost:12345, docs on :12346
./dev up --multi # demo and acme, at http://demo.masks.localhost:12345
./dev test       # every suite, in containers
./dev test unit  # one suite
./dev image      # run the production image and check each tenant's issuer and keys
./dev reference  # regenerate the reference pages
```

`./dev up` runs the provider, vite, the worker, and the doc site in the foreground, all reloading.
One tenant answers at `masks.localhost`. With `--multi` the stack declares `demo` and `acme`, and
Rails reads the tenant from the Host header.

|                       |                                                                            |
| --------------------- | -------------------------------------------------------------------------- |
| `unit`, `integration` | the provider                                                               |
| `provider`            | the engine installed into a fresh app through its generator                |
| `engine`, `client`    | the Rails engine and the plain Ruby half of the `masks` gem                |
| `web`                 | `@masks/client`                                                            |
| `conformance`         | the OpenID Foundation `oidcc-config` and `oidcc-basic` certification plans |

`./dev test` keeps going after a failure and names what failed at the end.
