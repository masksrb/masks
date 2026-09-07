# Changelog

## [0.7.0](https://github.com/masksrb/masks/compare/gem/v0.6.0...gem/v0.7.0) (2026-09-07)


### Features

* **client:** an app can act on a logout the issuer tells it about ([c103acb](https://github.com/masksrb/masks/commit/c103acbb27d8c96ad71439af2b6eba03024fbba0))
* **client:** an unconnected app walks straight into the handshake ([d9c88f2](https://github.com/masksrb/masks/commit/d9c88f25622eeeee535e77aac39e7044a9210ac4))


### Documentation

* hold the copyright as the masks authors ([1fb68bb](https://github.com/masksrb/masks/commit/1fb68bb24481d4c9560946e6d01d6114c4df231e))
* READMEs that match the code, and a server one that is not the scaffold ([2b1fc4f](https://github.com/masksrb/masks/commit/2b1fc4f8f2bbb32e4d2381f38f3f7ef446e8ee8f))
* references are generated from the code that defines them ([1ac0166](https://github.com/masksrb/masks/commit/1ac01668fcf2d69547f242982e922ddad92d89ed))
* the gem reference survives rdoc 8, and lists what a Concern adds ([cb13522](https://github.com/masksrb/masks/commit/cb135227bc177a41ad7e542c4aa796c836980409))


### Refactoring

* comments are gone; the code says what it does ([6857ff2](https://github.com/masksrb/masks/commit/6857ff20f1fbeee1471ff5ca07a591e0489066fa))
* rename the example tenant from jons to demo ([833a48b](https://github.com/masksrb/masks/commit/833a48bcdd03541bacede41ad077c3c8077467d6))
* take the owner's domain out of the boundary check ([b94c8df](https://github.com/masksrb/masks/commit/b94c8df8b72341c333a1369ceba59c7bc71ded68))

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
