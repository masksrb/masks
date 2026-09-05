# Changelog

## [0.6.0](https://github.com/masksrb/masks/compare/gem-v0.5.0...gem/v0.6.0) (2026-09-05)


### Features

* **server:** a namespace is a grant, so an app can grow its own scopes ([4e816e4](https://github.com/masksrb/masks/commit/4e816e4456de9cc05601b8eaa03773788e3178bb))
* **server:** people, avatars, and one page instead of three ([d50c444](https://github.com/masksrb/masks/commit/d50c4440812fc1c3a92e926ff6d533b9a69dae2a))


### Fixes

* **client:** an app whose issuer forgot it asks to be reconnected ([6956972](https://github.com/masksrb/masks/commit/695697233ca1ce35fa8b29ea74e58dd0d762b0a5))

## 0.5.0 — unreleased

First release carrying the consumer half in full. 0.4.0 predates the split described in
`plans/019` and should not be used.

- Discovery, PKCE authorization, token exchange, and token verification against a masks issuer.
- Rack middleware for a resource server.
- A Rails engine, mounted by the consuming app, covering the consumer half of the code flow.
- `rails generate masks:install`.
- `config.store` falls back to a default credential store instead of raising.

## 0.4.0

Withdrawn. An earlier design, published 2024-04-11 and marked "DO NOT USE".
