# Changelog

## [1.0.0](https://github.com/masksrb/masks/compare/gem/v0.6.0...gem/v1.0.0) (2026-09-12)


### ⚠ BREAKING CHANGES

* **client:** Masks::Client::Introspection#username is now #nickname.

### Features

* **client:** an app can act on a logout the issuer tells it about ([4d0b7f7](https://github.com/masksrb/masks/commit/4d0b7f77a74b0e416dda3e90413ad989a909f344))
* **client:** an unconnected app walks straight into the handshake ([040388e](https://github.com/masksrb/masks/commit/040388e188653f67ef7a59bc0aa9aef02ec351b2))


### Documentation

* hold the copyright as the masks authors ([cffdeb5](https://github.com/masksrb/masks/commit/cffdeb59f14eb02f6a9513d5f7cda21ebaee2171))
* READMEs that match the code, and a server one that is not the scaffold ([e0148e1](https://github.com/masksrb/masks/commit/e0148e14e0092731bcd095bc0fc22a1589c3acc0))
* references are generated from the code that defines them ([ba74550](https://github.com/masksrb/masks/commit/ba745501e651b797948e5abd5640a1825616100c))
* the gem reference survives rdoc 8, and lists what a Concern adds ([36df12e](https://github.com/masksrb/masks/commit/36df12e72cc52f5db650d16778ecc501bf9db14a))


### Refactoring

* **client:** an introspection answers a nickname, not a username ([f23dff5](https://github.com/masksrb/masks/commit/f23dff537320982d42a8e4823bea784a3d80ec33))
* comments are gone; the code says what it does ([0fc8e6a](https://github.com/masksrb/masks/commit/0fc8e6a4692e3f09831514b6d167c3e23d7db419))
* every suite is named for what it proves, under one test directory ([315b371](https://github.com/masksrb/masks/commit/315b371e64baa4441014669744a61c88341d27c7))
* rename the example tenant from jons to demo ([aef32a6](https://github.com/masksrb/masks/commit/aef32a670b4b3c696089c07bf15103e1d981eb00))
* take the owner's domain out of the boundary check ([df580ee](https://github.com/masksrb/masks/commit/df580ee1fb5820d30a57a88f3aa9825c97682725))

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
