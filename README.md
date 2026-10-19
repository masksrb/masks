<p align="center"><img src="engine/public/masks-public/icon.svg" width="120" alt="The masks rose window"></p>

<h1 align="center">masks</h1>

<p align="center"><strong>Self-hosted auth for the open web.</strong></p>

<p align="center">
  An OpenID Connect provider with a signing key for every tenant,<br>
  and the libraries your apps use to sign people in with it.
</p>

<p align="center">
  <a href="https://github.com/masksrb/masks/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/masksrb/masks/ci.yml?branch=main&label=CI" alt="CI"></a>
  <a href="https://github.com/masksrb/masks/actions/workflows/conformance.yml"><img src="https://img.shields.io/github/actions/workflow/status/masksrb/masks/conformance.yml?branch=main&label=OpenID%20conformance" alt="OpenID conformance"></a>
  <a href="https://github.com/masksrb/masks/pkgs/container/masks"><img src="https://img.shields.io/github/v/release/masksrb/masks?label=image" alt="Latest release"></a>
  <a href="https://rubygems.org/gems/masks"><img src="https://img.shields.io/gem/dt/masks?label=masks%20gem" alt="masks gem downloads"></a>
  <a href="https://www.npmjs.com/package/@masks/server"><img src="https://img.shields.io/npm/dm/%40masks%2Fserver?label=%40masks%2Fserver" alt="@masks/server downloads"></a>
  <a href="https://pypi.org/project/masks-client/"><img src="https://img.shields.io/pypi/dm/masks-client?label=masks-client" alt="masks-client downloads"></a>
  <a href="https://github.com/masksrb/masks/stargazers"><img src="https://img.shields.io/github/stars/masksrb/masks?style=flat" alt="Stars"></a>
</p>

<p align="center">
  <a href="https://masks.pages.dev/quickstart/"><b>Quickstart</b></a> ·
  <a href="https://masks.pages.dev">Documentation</a> ·
  <a href="https://masks.pages.dev/demo/">Demo</a> ·
  <a href="https://masks.pages.dev/guides/self-hosting/">Self-hosting</a>
</p>

## Run it

The image is `ghcr.io/masksrb/masks`.

- [Host it yourself](https://masks.pages.dev/guides/self-hosting/) with the image, Postgres, and a reverse proxy.
- [Mount it inside a Rails app](https://masks.pages.dev/reference/ruby/engine-mode/) with the `masks-server` gem.
- [Build your own masks server](https://masks.pages.dev/reference/ruby/server-mode/) as a Rails app, the way the image is built.
- [Put it in front of an app](https://masks.pages.dev/guides/forward-auth/) that has no sign-in, with Caddy, Traefik, or nginx.
- [Try it on your computer](https://masks.pages.dev/quickstart/#try-it-locally) from this repository.

## Libraries

| Language   | Package                                       | Reference                                                                |
| ---------- | --------------------------------------------- | ------------------------------------------------------------------------ |
| Ruby       | [`masks`](client/), [`masks-server`](engine/) | [Rails apps](https://masks.pages.dev/reference/ruby/)                    |
| JavaScript | [`@masks/server`](node/)                      | [Next.js, Express, Hono](https://masks.pages.dev/reference/javascript/)  |
| Browser    | [`@masks/client`](web/)                       | [Single-page apps](https://masks.pages.dev/reference/javascript/client/) |
| Python     | [`masks-client`](python/)                     | [FastAPI, Django, Flask](https://masks.pages.dev/reference/python/)      |
| Go         | [`github.com/masksrb/masks/go`](go/)          | [`net/http`](https://masks.pages.dev/reference/go/)                      |

## Security

Report a hole through [private vulnerability reporting](https://github.com/masksrb/masks/security/advisories/new). [SECURITY.md](SECURITY.md) says what counts and how fast masks answers.

## Contribute

You need Ruby and [Colima](https://github.com/abiosoft/colima).

- `./dev` runs the provider at `http://masks.localhost:12345` and the docs at `http://masks.localhost:12346`.
- `./dev test` runs every suite in containers.

[Try it locally](https://masks.pages.dev/quickstart/#try-it-locally) lists the rest.

## License

[MIT](LICENSE)
