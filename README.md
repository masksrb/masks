<p align="center"><img src="engine/public/masks-public/icon.svg" width="120" alt="The masks rose window"></p>

<h1 align="center">masks</h1>

<p align="center"><strong>Self-hosted auth for the open web.</strong></p>

<p align="center">
  An OpenID Connect provider with a signing key for every tenant,<br>
  and the libraries your apps use to sign people in with it.
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

## Contribute

You need Ruby and [Colima](https://github.com/abiosoft/colima).

- `./dev` runs the provider at `http://masks.localhost:12345` and the docs at `http://masks.localhost:12346`.
- `./dev test` runs every suite in containers.

[Try it locally](https://masks.pages.dev/quickstart/#try-it-locally) lists the rest.

## License

[MIT](LICENSE)
