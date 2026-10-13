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

```sh
docker pull ghcr.io/masksrb/masks:latest
```

Or add the [`masks-server`](engine/) gem to a Rails app, which mounts masks as a Rails engine:

```ruby
gem "masks-server"
```

See [Engine mode](https://masks.pages.dev/reference/ruby/engine-mode/) to mount it beside your own app, or [Server mode](https://masks.pages.dev/reference/ruby/server-mode/) to run an app that is only masks.

## Connect an app

| Language   | Package                              | Guide                                                                    |
| ---------- | ------------------------------------ | ------------------------------------------------------------------------ |
| Ruby       | [`masks`](client/)                   | [Rails and Rack](https://masks.pages.dev/reference/ruby/)                |
| JavaScript | [`@masks/server`](node/)             | [Next.js, Express, Hono](https://masks.pages.dev/reference/javascript/)  |
| Browser    | [`@masks/client`](web/)              | [Single-page apps](https://masks.pages.dev/reference/javascript/client/) |
| Python     | [`masks-client`](python/)            | [FastAPI, Django, Flask](https://masks.pages.dev/reference/python/)      |
| Go         | [`github.com/masksrb/masks/go`](go/) | [`net/http`](https://masks.pages.dev/reference/go/)                      |

## Develop

You need Docker with Compose, and Ruby.

- `./dev` runs the provider at `http://masks.localhost:12345` and the docs at `http://masks.localhost:12346`.
- `./dev test` runs every suite in containers.

[Try it locally](https://masks.pages.dev/quickstart/#try-it-locally) lists the rest.

## License

[MIT](LICENSE)
