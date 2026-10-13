# Changelog

## [0.2.0](https://github.com/masksrb/masks/compare/node-v0.1.0...node-v0.2.0) (2026-10-13)


### Features

* **node:** a client asks the issuer whether a token is active ([03a36e2](https://github.com/masksrb/masks/commit/03a36e206dab4fdeee89aa9b69d209160b2e6952))
* **node:** a client exchanges one token for another, held to its DPoP key ([7fe75a1](https://github.com/masksrb/masks/commit/7fe75a1177eb1d88b2ecd57682d1a912d3d8cb7d))
* **node:** a Next.js app on Auth.js signs people in through masks with masksAuth, which runs the handshake, refreshes once, and honors back-channel logout ([8d2b3be](https://github.com/masksrb/masks/commit/8d2b3be73fc9ed832ac9e2be8496ed0b12cc7b52))
* **node:** a server signs people in with the code flow, shakes hands with masks, and connects their providers ([5eb7bd4](https://github.com/masksrb/masks/commit/5eb7bd4a20f3e0dffb9cdc5c99c98ef64db0cba1))
* **node:** a sign-out everywhere comes back through /logout/return, the post-logout URI the handshake now registers ([0f1b67b](https://github.com/masksrb/masks/commit/0f1b67be3821de482046c06d9feaf8568ffc5a2f))
* **node:** a verifier names one store of seen DPoP proofs for every instance of an API ([9d096cf](https://github.com/masksrb/masks/commit/9d096cf67f1627fa22464270e24dfc30ad090712))
* **node:** an app connects a person's provider with startDelegation and finishDelegation, held to the person who started it ([c6b0b6b](https://github.com/masksrb/masks/commit/c6b0b6bf074f86a7827a2e31c1c795696bed4c04))
* **node:** an app enrolls and unenrolls its own machines ([4b1a162](https://github.com/masksrb/masks/commit/4b1a162f4fb672628a6975a1c56913b2d23b4bd8))
* **node:** an Auth.js app on several servers refreshes each sign-in once between them, through a refresh store they share ([ac50182](https://github.com/masksrb/masks/commit/ac50182d679159111b56065a3eefe6a0f5bb19ee))
* **node:** an Auth.js app shows the person's masks photo through its own avatar route and connects providers with delegations ([0febe03](https://github.com/masksrb/masks/commit/0febe03124e8e17638b9d24a110cf261f8070eed))
* **node:** an Auth.js app signs a person out of masks too, through /api/auth/masks/logout, and comes back to the app ([3820475](https://github.com/masksrb/masks/commit/38204754f43138934db83e805c38ab0aeacd85b6))
* **node:** Masks runs the whole sign-in for a JavaScript app, from the handshake to back-channel logout, on web-standard requests ([d7a75ad](https://github.com/masksrb/masks/commit/d7a75add2179a353af0c2df9a1388f30e5f3d590))
* **node:** Next.js, Express, and Hono apps sign people in through @masks/server/next, /express, and /hono ([c41ab0c](https://github.com/masksrb/masks/commit/c41ab0c3c71bf0671d7096d7a106e12c44413c7a))


### Fixes

* **node:** a guarded Express or Hono request refreshes an expired session once and sends one cookie for it ([e356782](https://github.com/masksrb/masks/commit/e3567821afffa8275b6e910fb4d6d8a81e5b0c8c))
* **node:** a Masks app checks tokens against the issuer it rediscovered, and keeps at most 1,000 verifiers ([717b7cb](https://github.com/masksrb/masks/commit/717b7cb2d9042b39be66b611f968bd34547c6528))
* **node:** a Masks session holds to the issuer that signed it in, so an app serving several tenants from one origin keeps their sessions apart ([8683cd6](https://github.com/masksrb/masks/commit/8683cd6defdcd041a7da9f2e436bda36d91a8677))
* **node:** a Next.js app on masksNext loads its route handlers under Turbopack, and the first visit to a protected page connects the app and comes back to that page ([a2bc150](https://github.com/masksrb/masks/commit/a2bc150923c7bbe7afda30253f3aa60001d2bf6f))
* **node:** a Next.js app that loads its masks setup twice shares one record of refreshes and logouts, and sees the credentials a handshake wrote ([b5c8d95](https://github.com/masksrb/masks/commit/b5c8d9593943c44f6eca5ecbe732545acdc07e03))
* **node:** a sign-in shakes hands again when masks no longer knows the app, and a signed-out visit to the handshake goes to afterSignOut ([5f38253](https://github.com/masksrb/masks/commit/5f382532a9ef19fa9385154e2620616a7d6993b1))
* **node:** a stale issuer is served while one refresh runs, and a masks that cannot be reached is asked again only after a back-off ([bfb8689](https://github.com/masksrb/masks/commit/bfb868960ab1e8bfe4e349691d732fea093015c3))
* **node:** a subject-wide logout ends a session signed in that second, a logout token is used once, and a read-only credential store refuses the handshake before masks registers a client ([ac8b0d6](https://github.com/masksrb/masks/commit/ac8b0d6c98e4b0234564b2bb63384c1a4e6475ae))
* **node:** a verifier that cannot check a token answers 503 without a challenge, so clients keep tokens that may be fine ([ffa2edc](https://github.com/masksrb/masks/commit/ffa2edc4fbc7eb0b767568314f42991c19643148))
* **node:** Masked.picture is the app's avatar route when masks holds a photo, so a Masks app's session no longer hands out an address that answers 401 ([4453b3e](https://github.com/masksrb/masks/commit/4453b3e9f1625d37a2240185633dd605bf8a6c4b))
* **node:** the in-memory session, refresh, and logout stores sweep out expired entries once a minute ([17c8e61](https://github.com/masksrb/masks/commit/17c8e61050f16a0c8d5407fcdd501c40756f4b2c))
* **node:** the Next.js the SDK is tested against is 16.3.8, past the image optimizer's request forgery and five cache and disclosure advisories ([1f96b88](https://github.com/masksrb/masks/commit/1f96b8866c68e63c72dbe43ff5ad2ca2c80f61fb))
* **node:** the Reconnect button on the connection page reaches masks, and a manager without the managing scopes is asked for them ([21eebaa](https://github.com/masksrb/masks/commit/21eebaa8efe0a3be6be8767de580b93fd8b1aaaf))
* **node:** while masks is down, a key already fetched keeps checking tokens for up to an hour, and the keys are fetched at most every 30 seconds ([6d54458](https://github.com/masksrb/masks/commit/6d54458f1deb3e12ca5a784bc1e12dd00049f0a2))


### Performance

* **node:** a Masks sign-in trusts a good answer about the app's registration for a minute, in place of asking masks at every start ([ace5544](https://github.com/masksrb/masks/commit/ace55441b7e91efabe6ff99cf684d7c942fa5a61))
* **node:** a request for a path masks does not answer passes through without resolving the issuer ([d88d104](https://github.com/masksrb/masks/commit/d88d104a8e1b73645dc99fbce32360a286c2ac07))
* **node:** Express streams the answers masks gives it, so an avatar passes through without being held in memory ([5a4a536](https://github.com/masksrb/masks/commit/5a4a536c830276124d66918c16230478ddc9a2f1))


### Documentation

* each language has a group under Reference, with an overview, a page per framework, and its API reference ([64b7837](https://github.com/masksrb/masks/commit/64b7837e0484d11ddd5b4d926fc4aa800c06ed81))
* each SDK keeps a TODO of the cleanups, security follow-ups, and testing left from the framework integrations ([4c4353b](https://github.com/masksrb/masks/commit/4c4353b63713700034c78f3d3c0b3b45ac7b50b3))
* **node:** the JavaScript apps guide covers Next.js, Express, and Hono from the handshake to enrollment, and the README leads with signing people in ([144dc6c](https://github.com/masksrb/masks/commit/144dc6c656e760fec17d56bc85247bac95b34c53))
* **node:** the TODO records the live Express and Hono runs ([d6cc664](https://github.com/masksrb/masks/commit/d6cc664e4774082cdfc52113a4f33f0c7f32f166))


### Refactoring

* **node:** masksAuth and Masks share one record of how logouts and approved scopes work, and a stand-in provider can never finish a sign-in ([bffb480](https://github.com/masksrb/masks/commit/bffb48069277a54245eee1854379d1f9310ef2f3))
* **node:** the adapters share Masks.from, the Next.js helpers read the proxy's path through localPath, and dead state is gone ([47d723a](https://github.com/masksrb/masks/commit/47d723a3cc1485c26260dab208336589d0a98e6b))
* **node:** Verifier builds the Bearer and DPoP challenges for a 403 as well as a 401 ([d79946c](https://github.com/masksrb/masks/commit/d79946c8613586328ccbe9d5edc26126c0fe6c5f))

## 0.1.0 (2026-10-11)


### Features

* **node:** a JavaScript server signs in to masks as itself with a key, holds its tokens to a second key with DPoP, enrolls with an initial access token, and an API checks those tokens on Node, Next.js, Bun, or Deno ([24e1a86](https://github.com/masksrb/masks/commit/24e1a8646894e1dde6edc11bc0eff7c823978c6c))


### Refactoring

* **node:** the JavaScript server SDK is published as @masks/server, beside @masks/client for the browser ([f5664e0](https://github.com/masksrb/masks/commit/f5664e0caf9ddae9facc5fae09a990835eec4866))
