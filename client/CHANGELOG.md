# Changelog

## [0.10.0](https://github.com/masksrb/masks/compare/gem/v0.9.2...gem/v0.10.0) (2026-10-10)


### Features

* **client:** a sign-in can ask for a step-up scope the app offers, and masks grants it only to people whose scopes cover it ([84b43d8](https://github.com/masksrb/masks/commit/84b43d8c091440a5a9b75721b56f9ced27c9f82f))
* **client:** masks_require_scope! guards an action with a step-up scope, sending its holder through masks once and refusing everyone else ([fce327e](https://github.com/masksrb/masks/commit/fce327edae9d6166e8bc163d85c4ca8e6548e1eb))

## [0.9.2](https://github.com/masksrb/masks/compare/gem/v0.9.1...gem/v0.9.2) (2026-10-10)


### Documentation

* the examples name xixo, the resource server once called uris ([ca80f20](https://github.com/masksrb/masks/commit/ca80f20c9aea4ee6a3e7cd6c76c69425e4c800e3))

## [0.9.1](https://github.com/masksrb/masks/compare/gem/v0.9.0...gem/v0.9.1) (2026-10-04)


### Fixes

* **client:** an error the issuer sends back is shown rather than retried, and the engine tests hold the new callback behaviour ([36adb9b](https://github.com/masksrb/masks/commit/36adb9b57a2379b8d7ce1d16f2e04e8c244baa7d))

## [0.9.0](https://github.com/masksrb/masks/compare/gem/v0.8.0...gem/v0.9.0) (2026-10-04)


### ⚠ BREAKING CHANGES

* **client:** a connected app refuses reconnecting and disconnecting until config.manages is set, for example config.manages = ->(request, identity) { identity["sub"] == ENV["OWNER_SUB"] }.

### Fixes

* **client:** a resource server refuses a DPoP-bound token presented as Bearer, and checks the proof one presented as DPoP ([9a3fe8a](https://github.com/masksrb/masks/commit/9a3fe8adac09fd70a7059674d8c34333c8f3ff92))
* **client:** a return_to a browser would read as another host is refused, and signing out revokes the refresh token ([de27168](https://github.com/masksrb/masks/commit/de2716872955ba124a8a3ec1dbe07cb043fd0260))
* **client:** a sign-in callback this browser no longer holds goes on to the app or starts sign-in again, instead of ending on an error ([a1ba84c](https://github.com/masksrb/masks/commit/a1ba84c4a974897bdb80b1f32da5c0b72f83ca79))
* **client:** every resource in a process shares one store of seen DPoP proofs, and a refused proof is challenged with the DPoP scheme ([f8d1fe2](https://github.com/masksrb/masks/commit/f8d1fe2487e0705c914ea3d3ae7f686152cad6b3))
* **client:** only somebody config.manages approves can reconnect or disconnect a connected app ([5665129](https://github.com/masksrb/masks/commit/566512979dc00a36148de57b4ea9954fc68db10b))


### Documentation

* every guide, the reference prose, and the READMEs are checked against the code, shortened, and corrected ([94782d1](https://github.com/masksrb/masks/commit/94782d1fbfe363e90c40f0c728a241de9738e138))
* the plan holds only what is left, and the READMEs match the engine layout and the code ([1615722](https://github.com/masksrb/masks/commit/1615722f88ae5f7d19955ff686dcef9f64a6326f))


### Refactoring

* **client:** the issuer version check nothing called, Registry#urls and Verifier#tenant go ([6b8cf05](https://github.com/masksrb/masks/commit/6b8cf0550b96f6b1b3b415ff27f655f90614bdfe))
* **engine:** deleting and downloading an account share one check for a fresh sign-in, and PKCE uses the client's one base64url digest ([6c08fcf](https://github.com/masksrb/masks/commit/6c08fcf709a08dbafd0a551801eaf43a4c325b75))
* **engine:** one partial carries a tenant's email wording, one query loads it, and authorization_details narrow in one place ([1b2df29](https://github.com/masksrb/masks/commit/1b2df29380b2c2c8dc6b87d45d60b4ef23255b26))

## [0.8.0](https://github.com/masksrb/masks/compare/gem/v0.7.0...gem/v0.8.0) (2026-09-28)


### ⚠ BREAKING CHANGES

* a resource server on an older gem still accepts the new tokens, but this gem refuses access tokens from a server that does not type them.

### Features

* an access token is typed at+jwt, and nothing takes a token of another type in its place ([d0b4cfd](https://github.com/masksrb/masks/commit/d0b4cfdf802053359695495d417225e3a1578302))
* **client:** a Rails app lists the organizations a person belongs to and links them to another ([7f0d223](https://github.com/masksrb/masks/commit/7f0d2237799e04551d2c403de695c704e5455db8))
* **client:** a Rails app names the organization a person signs in to, reads their role, and keeps pages and APIs to members in a role ([579cecc](https://github.com/masksrb/masks/commit/579ceccac1c0137dfa1ed7a3894dea61e5cdd67e))
* **client:** a session signs its own client assertions, and asks for a token of its own ([614248b](https://github.com/masksrb/masks/commit/614248b70a3ee517fbd3c1f7151b66ec6406b487))
* **client:** an exchange hands over an ID token or an actor token ([6b67766](https://github.com/masksrb/masks/commit/6b67766ce275b9578d575349256638adddd5a599))
* **client:** the session says where the person manages their account, as account_url ([1d36e1d](https://github.com/masksrb/masks/commit/1d36e1d4daa8c5acfc9133a1896aa9384771dbd6))


### Documentation

* Rails apps covers client, server, and engine mode ([41454a2](https://github.com/masksrb/masks/commit/41454a242438e4df246dcbc4dce94b6d8a022239))


### Refactoring

* **client:** an organization key is checked in one place, and a refresh renews the whole identity from userinfo ([b349aae](https://github.com/masksrb/masks/commit/b349aaec4dd5c9790c72dd1dc8f91016a2adceea))

## [0.7.0](https://github.com/masksrb/masks/compare/gem/v0.6.0...gem/v0.7.0) (2026-09-13)


### ⚠ BREAKING CHANGES

* **client:** Masks::Client::Introspection#username is now #nickname.

### Features

* **client:** an app can act on a logout the issuer tells it about ([4d0b7f7](https://github.com/masksrb/masks/commit/4d0b7f77a74b0e416dda3e90413ad989a909f344))
* **client:** an app that delegates asks its handshake for masks:delegate: and the token exchange ([912e856](https://github.com/masksrb/masks/commit/912e856b00a9f27d59af861cdb35da518fa862bc))
* **client:** an app that delegates registers where connecting a person's account comes back to ([738fba6](https://github.com/masksrb/masks/commit/738fba67e544f7c8a9a15cd55befbd66696b707b))
* **client:** an unconnected app walks straight into the handshake ([040388e](https://github.com/masksrb/masks/commit/040388e188653f67ef7a59bc0aa9aef02ec351b2))
* **server:** an application is let use somebody's account elsewhere through a delegation ([4b7048c](https://github.com/masksrb/masks/commit/4b7048cb8ac4e174b9359a070b7a2d942a1c410d))


### Fixes

* **client:** back-channel logout says 501 when the app does nothing about it ([60e1125](https://github.com/masksrb/masks/commit/60e1125c02adec7c822c6d3757210e825bb66cfc))


### Documentation

* hold the copyright as the masks authors ([cffdeb5](https://github.com/masksrb/masks/commit/cffdeb59f14eb02f6a9513d5f7cda21ebaee2171))
* READMEs that match the code, and a server one that is not the scaffold ([e0148e1](https://github.com/masksrb/masks/commit/e0148e14e0092731bcd095bc0fc22a1589c3acc0))
* references are generated from the code that defines them ([ba74550](https://github.com/masksrb/masks/commit/ba745501e651b797948e5abd5640a1825616100c))
* the gem reference survives rdoc 8, and lists what a Concern adds ([36df12e](https://github.com/masksrb/masks/commit/36df12e72cc52f5db650d16778ecc501bf9db14a))
* the rose window is the site's logo, favicon and hero, and heads every README ([72176e4](https://github.com/masksrb/masks/commit/72176e49c81bc0a5d6730f3b9e5eaa693db8a659))


### Refactoring

* **client:** an introspection answers a nickname, not a username ([f23dff5](https://github.com/masksrb/masks/commit/f23dff537320982d42a8e4823bea784a3d80ec33))
* comments are gone; the code says what it does ([0fc8e6a](https://github.com/masksrb/masks/commit/0fc8e6a4692e3f09831514b6d167c3e23d7db419))
* every suite is named for what it proves, under one test directory ([315b371](https://github.com/masksrb/masks/commit/315b371e64baa4441014669744a61c88341d27c7))
* rename the example tenant from jons to demo ([aef32a6](https://github.com/masksrb/masks/commit/aef32a670b4b3c696089c07bf15103e1d981eb00))
* **server:** delegation shares what sign-in and linking already had, and asks the database less ([44b8c4d](https://github.com/masksrb/masks/commit/44b8c4d303dfcc6de60f98d7824c544bd67e347c))
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
