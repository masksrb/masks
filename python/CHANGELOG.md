# Changelog

## [0.2.0](https://github.com/masksrb/masks/compare/python-v0.1.0...python-v0.2.0) (2026-10-13)


### Features

* **python:** a FastAPI app keeps its sessions in an async store, so waiting on Redis or a database holds up no other request ([f285a95](https://github.com/masksrb/masks/commit/f285a9521f9a40552c5f63d0318653b333c39d87))
* **python:** a FastAPI app signs people in through masks, guards routes by privilege, and accepts tokens ([6265b69](https://github.com/masksrb/masks/commit/6265b696fd4c53b33879afeac20704e5ff28539d))
* **python:** a Python app signs people in with the code flow, shakes hands with masks, and holds delegations ([f649f92](https://github.com/masksrb/masks/commit/f649f92e62baadaf4a16bbb1893c418a20e8e4b4))
* **python:** a sign-in checks that masks still knows the app, and sends it back through the handshake when not ([d1a16cd](https://github.com/masksrb/masks/commit/d1a16cd442ef55e3b724d181c72b0f71f0389ba1))
* **python:** a verifier remembers DPoP proofs in a replay store that several processes can share ([209c4ca](https://github.com/masksrb/masks/commit/209c4ca460de76ae8d01f1b64a6b45683c8643d4))
* **python:** an app enrolls and unenrolls its own machines, introspects tokens, and exchanges them ([9bc4070](https://github.com/masksrb/masks/commit/9bc4070ec296f1d9e345da89a471192a99b7f8c8))
* **python:** Django and Flask apps sign people in through masks with the same routes and privileges ([a662f29](https://github.com/masksrb/masks/commit/a662f29a7134ba01d42f811f9bd6d902f0732873))
* **python:** requests that share an expired sign-in refresh it once, and back-channel logout ends cookie sessions ([7b5d731](https://github.com/masksrb/masks/commit/7b5d731a75af344fad66c0c4fda6385a751b6936))


### Fixes

* **python:** a session holds to the issuer that signed it in, a back-channel request over 64 KB is refused unread, and an answer that changes the session stays out of shared caches ([443c695](https://github.com/masksrb/masks/commit/443c695046e018db13aa795dd034dc86393393fc))
* **python:** a signed-in person's picture is the app's avatar route when masks holds a photo, so it no longer answers 401 in the browser ([ac6283b](https://github.com/masksrb/masks/commit/ac6283b5b5569e1c740aa4e5bfd0a938179a5f8e))
* **python:** a verifier that cannot reach its keys or replay store answers 503 instead of rejecting the token ([0396e55](https://github.com/masksrb/masks/commit/0396e55fd80793e225ec1893f51fbdaf60c53da0))
* **python:** Flask and Django read the session only when a request needs it, cap a back-channel request at 64 KB, and refuse an async store at startup ([09ccf0e](https://github.com/masksrb/masks/commit/09ccf0e38bc3124df6ce3ccd51c4dcab31906a85))
* **python:** signing out everywhere returns to a registered address, and no other site can sign anyone out ([e12d0ec](https://github.com/masksrb/masks/commit/e12d0ec3ba8042eca34a97dbe2e65598b701d73f))
* **python:** the Reconnect button on the connection page reaches masks, and no other site can frame a masks page ([4e204e0](https://github.com/masksrb/masks/commit/4e204e0f972e8109b15fc885d04e8e6e926a91d3))


### Documentation

* each language has a group under Reference, with an overview, a page per framework, and its API reference ([64b7837](https://github.com/masksrb/masks/commit/64b7837e0484d11ddd5b4d926fc4aa800c06ed81))
* each language's guide sits in the sidebar, and Other languages is gone ([86e863f](https://github.com/masksrb/masks/commit/86e863f52d92c7aaf9649d284e70787e17ac1b6e))
* each SDK keeps a TODO of the cleanups, security follow-ups, and testing left from the framework integrations ([4c4353b](https://github.com/masksrb/masks/commit/4c4353b63713700034c78f3d3c0b3b45ac7b50b3))
* **python:** the Python SDK installs from its release tag, since masks-client is not on PyPI yet ([f59ee0f](https://github.com/masksrb/masks/commit/f59ee0f5a93001a0e315684ede4b37e25c79e177))
* **python:** the TODO records the live FastAPI run and what it left out ([2840e96](https://github.com/masksrb/masks/commit/2840e967840f3c744b729d31bfc896733d15844c))
* **python:** the TODO records the live Flask run ([765c5b1](https://github.com/masksrb/masks/commit/765c5b15e99c734ddc7bb93b00dd8e16e332d3b3))

## 0.1.0 (2026-10-11)


### Features

* **python:** a Python service or machine signs in to masks as itself with a key, holds its tokens to a second key with DPoP, enrolls with an initial access token, and an API checks those tokens ([ecbc546](https://github.com/masksrb/masks/commit/ecbc5460507ab7a2e1a99e4d17325266ced7d14d))
