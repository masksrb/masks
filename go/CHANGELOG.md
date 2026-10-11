# Changelog

## 0.1.0 (2026-10-11)


### Features

* **go:** a Go service or machine signs in to masks as itself with a key, holds its tokens to a second key with DPoP, enrolls with an initial access token, and an API checks those tokens ([7bedecc](https://github.com/masksrb/masks/commit/7bedecc31afa13070e2c36d7e8d4097dcf90a87c))


### Refactoring

* **engine:** the services that send mail and texts are senders throughout, in the API, the events, and the database ([2f79202](https://github.com/masksrb/masks/commit/2f79202bbd0931df084e4dadc7c89d7a7e723cad))
* **go:** every call to masks goes through one send and decode, the issuer's DPoP nonce is remembered, keys sign with signers built once, and the verifier checks a token without serializing requests ([9c3d325](https://github.com/masksrb/masks/commit/9c3d3259d6f819b1dd44ee4c6a0c1aeb55ecef6e))
