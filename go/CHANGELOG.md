# Changelog

## [0.3.1](https://github.com/masksrb/masks/compare/go/v0.3.0...go/v0.3.1) (2026-10-14)


### Fixes

* **go:** a sign-out link with no Sec-Fetch-Site shows a Sign out button instead of signing the person out ([6d8501c](https://github.com/masksrb/masks/commit/6d8501c41bc672c7625c78b03d2c5416e7b1e1fe))
* **go:** the guard decides where a request came from, so a sign-out by POST that names no site is refused and the Sign out page posts back to its own address ([3d74076](https://github.com/masksrb/masks/commit/3d740768340f93e9e79a61c928235e076d2ce589))

## [0.3.0](https://github.com/masksrb/masks/compare/go/v0.2.0...go/v0.3.0) (2026-10-14)


### Features

* **go:** a go/web Person checks any privilege with Holds and Member, and NameFor names the app for each request ([0cd048a](https://github.com/masksrb/masks/commit/0cd048a41098062c8f4e7e9e0c4f097af3cfa498))
* **go:** go/web/redisstore keeps a web app's sessions, logouts, proofs, and refreshes in Redis ([bb12142](https://github.com/masksrb/masks/commit/bb12142beb6d6d626699f74b58cae71cd753b56d))
* **go:** one Store holds a web app's sessions, logouts, proofs, and refreshes, so instances behind a load balancer share a refresh instead of racing it ([7ab23ac](https://github.com/masksrb/masks/commit/7ab23ac07210560f39602d774aeb84bc9ef4a474))


### Fixes

* **go:** a back-channel logout that LoggedOut could not finish can be sent again, and a sign-out form is read up to 64 KiB ([794629e](https://github.com/masksrb/masks/commit/794629efc5cf88a2de1fa07487bdc7be38c8bc30))
* **go:** a back-channel logout token without exp is refused, so its jti is remembered for as long as the token is accepted ([a8c7aed](https://github.com/masksrb/masks/commit/a8c7aedd39c0582fc1761569c26f179f4804e78d))
* **go:** a callback that no sign-in in this browser started no longer repeats the error text in its URL ([02bbe26](https://github.com/masksrb/masks/commit/02bbe26216556929c52c8214e84d68418a4775c9))
* **go:** a delegation needs somebody signed in, and is held to the person who started it ([fbf9334](https://github.com/masksrb/masks/commit/fbf9334d0f83b64feedd21baeb3b57997ef30687))
* **go:** a request that carries a credential never follows a redirect, so a client secret or refresh token stays with the issuer ([1a2c015](https://github.com/masksrb/masks/commit/1a2c015dda0ea860368d0a70d34a120a1291cb11))
* **go:** a request with no token gets a challenge with no error code, and a refused token is described in plain words ([c35c15e](https://github.com/masksrb/masks/commit/c35c15e9ecad5e2def4b270f8819e22dccb0f705))
* **go:** a sign-in that asked for max_age is refused when the ID token's auth_time is older ([04773ce](https://github.com/masksrb/masks/commit/04773cea4a11f3679fdf74e694faff3511ee2157))
* **go:** an app's credentials name their issuer, so one tenant's client secret is never sent to another ([b38438d](https://github.com/masksrb/masks/commit/b38438d5eb1f0a6d0e77e9539cccfbaf9d463585))
* **go:** processes that share masks.json see each other's handshake, and one never deletes credentials it did not hold ([64bfba9](https://github.com/masksrb/masks/commit/64bfba9795aed47fc49b4915dd4575f4e3cde98a))
* **go:** ReuseTokenSource without a fetch answers an error when its token expires, and the README covers max_age and redirects ([9bfe459](https://github.com/masksrb/masks/commit/9bfe459a8425e23e68f2de69c61941aa36a1de9d))


### Performance

* **go:** go/web serves a stale issuer while one request discovers it again, and waits before asking an issuer that is down ([e456ea1](https://github.com/masksrb/masks/commit/e456ea19e33904687e0e95edb51c0e4c2dc3f2f3))


### Documentation

* every guide, SDK reference, and README says what masks does now, in fewer words ([7046f86](https://github.com/masksrb/masks/commit/7046f862c774f05407d92cd19779f53bf0b62595))
* **go:** the to-do list records the live DPoP run and the audit's open findings ([58c4eea](https://github.com/masksrb/masks/commit/58c4eeae9232d210961c4f0434292535f1cb2659))
* **go:** the to-do list records the live run of go/web against masks ([5cadff8](https://github.com/masksrb/masks/commit/5cadff836c5b04faa489f2c82f5970a08499f702))


### Refactoring

* **go:** each go/web request loads its session once, and the resource server reuses the client package's challenges ([1ce05ed](https://github.com/masksrb/masks/commit/1ce05ed633126ddeb1a0c3e2ccdde7a23bc6249a))
* **go:** go/web names the signed-in party an Actor, as masks does ([b1a9b73](https://github.com/masksrb/masks/commit/b1a9b73b2086f05d4c247f635e4adbac0bbcab50))
* **go:** the avatar proxy sends the person's token through the client's own transport ([44d794d](https://github.com/masksrb/masks/commit/44d794dd170112efc09ee60e06cbd9f4fe8fce04))

## [0.2.0](https://github.com/masksrb/masks/compare/go/v0.1.0...go/v0.2.0) (2026-10-13)


### Features

* **go:** a client shakes hands with masks, signs people in with the code flow, ends their session, and connects delegations ([5be59e4](https://github.com/masksrb/masks/commit/5be59e41b2e40bbc33355ff184785bf5c143a20a))
* **go:** a Go web app signs people in through masks with go/web, as a Rails app does with Masks::Rails ([ca8d655](https://github.com/masksrb/masks/commit/ca8d65542165fd165b1eac9864152c9a06572dc4))
* **go:** a handshake registers the app's post-logout URI, and go/web returns from masks' sign-out through /auth/logout/return ([65ff811](https://github.com/masksrb/masks/commit/65ff811cb229f590392a5bf3c2b2743e1e527ea7))
* **go:** an app enrolls and unenrolls its machines, a client introspects and exchanges tokens, and a verifier shares its replay store ([0e014fb](https://github.com/masksrb/masks/commit/0e014fb8ab37834b522b2948ac4cf25e7f245913))


### Fixes

* **go:** go/web keeps a session when masks is unavailable, refuses a cross-site sign-out by any method, and connects only when it can save the credentials ([fa16e8f](https://github.com/masksrb/masks/commit/fa16e8fe99ecff17e7f2d33e783308c4dd8515c4))


### Performance

* **go:** go/web's memory session and departure stores share one expiring map that sweeps at most once a second ([93c2ba0](https://github.com/masksrb/masks/commit/93c2ba02b605f8dc72285ef808bc58fcb1503817))


### Documentation

* each language has a group under Reference, with an overview, a page per framework, and its API reference ([64b7837](https://github.com/masksrb/masks/commit/64b7837e0484d11ddd5b4d926fc4aa800c06ed81))
* each SDK keeps a TODO of the cleanups, security follow-ups, and testing left from the framework integrations ([4c4353b](https://github.com/masksrb/masks/commit/4c4353b63713700034c78f3d3c0b3b45ac7b50b3))
* **go:** the Go apps guide covers go/web from the handshake to enrolling machines ([6c6ee74](https://github.com/masksrb/masks/commit/6c6ee7411b8be6aae67d9064a369bed515177117))


### Refactoring

* **go:** a verifier builds its own Bearer and DPoP challenges, pointing at the resource metadata ([2aaf06c](https://github.com/masksrb/masks/commit/2aaf06cc98844ad3e2b127a54905ed53e63b774f))

## 0.1.0 (2026-10-11)


### Features

* **go:** a Go service or machine signs in to masks as itself with a key, holds its tokens to a second key with DPoP, enrolls with an initial access token, and an API checks those tokens ([7bedecc](https://github.com/masksrb/masks/commit/7bedecc31afa13070e2c36d7e8d4097dcf90a87c))


### Refactoring

* **engine:** the services that send mail and texts are senders throughout, in the API, the events, and the database ([2f79202](https://github.com/masksrb/masks/commit/2f79202bbd0931df084e4dadc7c89d7a7e723cad))
* **go:** every call to masks goes through one send and decode, the issuer's DPoP nonce is remembered, keys sign with signers built once, and the verifier checks a token without serializing requests ([9c3d325](https://github.com/masksrb/masks/commit/9c3d3259d6f819b1dd44ee4c6a0c1aeb55ecef6e))
