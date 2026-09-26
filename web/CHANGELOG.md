# Changelog

## [3.0.0](https://github.com/masksrb/masks/compare/client-v2.2.0...client-v3.0.0) (2026-09-26)


### ⚠ BREAKING CHANGES

* a resource server on an older gem still accepts the new tokens, but this gem refuses access tokens from a server that does not type them.

### Features

* an access token is typed at+jwt, and nothing takes a token of another type in its place ([d0b4cfd](https://github.com/masksrb/masks/commit/d0b4cfdf802053359695495d417225e3a1578302))
* **client:** the session says where the person manages their account, as account_url ([1d36e1d](https://github.com/masksrb/masks/commit/1d36e1d4daa8c5acfc9133a1896aa9384771dbd6))
* **web:** a Person component renders who is signed in, for React and Svelte ([2fab015](https://github.com/masksrb/masks/commit/2fab015632044f8b14a0bb799b73e23a21500605))


### Documentation

* Rails apps covers client, server, and engine mode ([41454a2](https://github.com/masksrb/masks/commit/41454a242438e4df246dcbc4dce94b6d8a022239))

## [2.2.0](https://github.com/masksrb/masks/compare/client-v2.1.0...client-v2.2.0) (2026-09-13)


### Features

* **client:** the browser package builds on typescript 7 ([85975ce](https://github.com/masksrb/masks/commit/85975cebe1e393f6e283bc1531f5843fd886d674))
* **client:** verifyIdToken's options type is exported ([3220524](https://github.com/masksrb/masks/commit/3220524a1507a78348aa1625fac1937ff7803a69))
* the server is published as a container image ([16630a8](https://github.com/masksrb/masks/commit/16630a8e71c5244e404d4f7d7a3a8dc016117eb2))


### Fixes

* **client:** a key the issuer rotated in is found even while the browser holds a cached key set ([b4a1a9f](https://github.com/masksrb/masks/commit/b4a1a9fbf2cb176da5fc41f68c29a610cda5d00f))


### Documentation

* hold the copyright as the masks authors ([cffdeb5](https://github.com/masksrb/masks/commit/cffdeb59f14eb02f6a9513d5f7cda21ebaee2171))
* READMEs that match the code, and a server one that is not the scaffold ([e0148e1](https://github.com/masksrb/masks/commit/e0148e14e0092731bcd095bc0fc22a1589c3acc0))
* references are generated from the code that defines them ([ba74550](https://github.com/masksrb/masks/commit/ba745501e651b797948e5abd5640a1825616100c))
* the rose window is the site's logo, favicon and hero, and heads every README ([72176e4](https://github.com/masksrb/masks/commit/72176e49c81bc0a5d6730f3b9e5eaa693db8a659))


### Refactoring

* rename the example tenant from jons to demo ([aef32a6](https://github.com/masksrb/masks/commit/aef32a670b4b3c696089c07bf15103e1d981eb00))

## [2.1.0](https://github.com/masksrb/masks/compare/client-v2.0.0...client-v2.1.0) (2026-09-05)


### Features

* **server:** people, avatars, and one page instead of three ([d50c444](https://github.com/masksrb/masks/commit/d50c4440812fc1c3a92e926ff6d533b9a69dae2a))

## 2.0.0 — unreleased

First real release. Session mode against a backend-for-frontend, and the PKCE code flow in the
browser.

The major version is not continuous with 1.0.0: that version was a name reservation published
2025-02-06, containing a single 209-byte stub and no client at all. Anything resolving `^1.0.0`
is resolving the placeholder, which is why this release does not continue that line.

## 1.0.0

Withdrawn. A name reservation, not an implementation.
