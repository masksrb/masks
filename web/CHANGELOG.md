# Changelog

## [2.2.0](https://github.com/masksrb/masks/compare/client-v2.1.0...client-v2.2.0) (2026-09-07)


### Features

* **client:** the browser package builds on typescript 7 ([c42aa79](https://github.com/masksrb/masks/commit/c42aa791921d47e161a9e9b7d751fac9581c4822))
* **client:** verifyIdToken's options type is exported ([eca09f8](https://github.com/masksrb/masks/commit/eca09f8ccadbda62b94bbbc139fbbbb0756abb56))
* the server is published as a container image ([5ea221e](https://github.com/masksrb/masks/commit/5ea221e8a3b445e2fcbd5d01cd968cfbba20ef42))


### Documentation

* hold the copyright as the masks authors ([1fb68bb](https://github.com/masksrb/masks/commit/1fb68bb24481d4c9560946e6d01d6114c4df231e))
* READMEs that match the code, and a server one that is not the scaffold ([2b1fc4f](https://github.com/masksrb/masks/commit/2b1fc4f8f2bbb32e4d2381f38f3f7ef446e8ee8f))
* references are generated from the code that defines them ([1ac0166](https://github.com/masksrb/masks/commit/1ac01668fcf2d69547f242982e922ddad92d89ed))


### Refactoring

* rename the example tenant from jons to demo ([833a48b](https://github.com/masksrb/masks/commit/833a48bcdd03541bacede41ad077c3c8077467d6))

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
