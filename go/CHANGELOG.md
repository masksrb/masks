# Changelog

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
