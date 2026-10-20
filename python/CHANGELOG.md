# Changelog

## [0.3.2](https://github.com/masksrb/masks/compare/python-v0.3.1...python-v0.3.2) (2026-10-20)


### Fixes

* **client:** a sign-in older than the max_age the app asked for is refused ([7116e24](https://github.com/masksrb/masks/commit/7116e24e73dedcca6ce54aa4347100b7d4714e3a)), closes [#161](https://github.com/masksrb/masks/issues/161)
* **client:** the last good issuer and keys are served while masks is down ([1423d1e](https://github.com/masksrb/masks/commit/1423d1ea6b7968aa66ad2a2ca63180effa4c1002)), closes [#162](https://github.com/masksrb/masks/issues/162)

## [0.3.1](https://github.com/masksrb/masks/compare/python-v0.3.0...python-v0.3.1) (2026-10-19)


### Fixes

* **python:** a sign-out link from a browser that names no site shows a Sign out button, so another site's link cannot sign anybody out ([8a7ab01](https://github.com/masksrb/masks/commit/8a7ab014d45e2741c36aa2cd979ea1e53579536a))
* **python:** one provenance check guards every browser route, so a sign-out by POST that names no site is refused and the Sign out page posts back to its own address ([be39f6a](https://github.com/masksrb/masks/commit/be39f6a890539e811653e7460f1571af661ab3e3))

## [0.3.0](https://github.com/masksrb/masks/compare/python-v0.2.0...python-v0.3.0) (2026-10-14)


### Features

* **python:** FastAPI, Flask, and Django start and finish a delegation in one call each, held to the person who started it ([6379371](https://github.com/masksrb/masks/commit/6379371d2875a0a51ba34edf75fc1e7f663e6578))
* **python:** one store setting shares refreshes, logouts, and DPoP proofs across processes, with Redis stores built in ([acc525f](https://github.com/masksrb/masks/commit/acc525f2fae62024df322e98178d4692dca899f4))


### Fixes

* **python:** a back-channel logout that logged_out or the session store could not finish can be sent again ([2303852](https://github.com/masksrb/masks/commit/230385229dad987e2931fe5a62736b3d72360027))
* **python:** a logout token whose departure cannot be saved is taken again, and a store outage during a refresh leaves the session as it is ([f348221](https://github.com/masksrb/masks/commit/f348221c4a7dce4d1c7ee0354d933daf06131174))
* **python:** a session too large for one cookie is split across up to eight, as Go and Node do ([9c8b197](https://github.com/masksrb/masks/commit/9c8b19718321ae625701d9f866d6e77b15e90d38))
* **python:** a sign-in error shows only for a sign-in this browser started, and an outage page no longer shows the error behind it ([8a40872](https://github.com/masksrb/masks/commit/8a40872a965ed6bd5f2da6555e700f58d496d864))
* **python:** an app's credentials name their issuer, so one tenant's client secret is never sent to another ([89cf58a](https://github.com/masksrb/masks/commit/89cf58a6e58e7369115709e1e24460c6e9bf0c3b))
* **python:** FileCredentials checks it can write its folder before the handshake registers, and reports a file it cannot read ([0e62845](https://github.com/masksrb/masks/commit/0e62845e2bdf912b2d6e5761d19822366610a05c))
* **python:** Reconnect and Disconnect work in Django, since masks' own routes check their forms' origin themselves ([77a5ac9](https://github.com/masksrb/masks/commit/77a5ac9b85d24c43e643fbe28437bee38a8d7d8b))
* **python:** the ASGI middleware sends no error code to a request with no token, and a refused token is described in plain words ([b82814c](https://github.com/masksrb/masks/commit/b82814ce463ac3da8819d78c2f252efe30561ebf))


### Performance

* **python:** a token's header is read from its first segment alone before PyJWT checks the whole token ([8650bd7](https://github.com/masksrb/masks/commit/8650bd702ba0ad1080d02787f6edd03c30d061f7))


### Documentation

* comments and pages no longer claim what masks stopped doing ([e0b1ba0](https://github.com/masksrb/masks/commit/e0b1ba0b71ccae8683b605f9442ee16c4afb5dd4))
* every guide, SDK reference, and README says what masks does now, in fewer words ([7046f86](https://github.com/masksrb/masks/commit/7046f862c774f05407d92cd19779f53bf0b62595))
* **python:** the README covers the web integrations, the handshake, and the code flow ([9ae0ced](https://github.com/masksrb/masks/commit/9ae0cedfdfb04390d00efded096a4ed1304a8c58))
* **python:** the README installs masks-client from PyPI ([706bd20](https://github.com/masksrb/masks/commit/706bd20e177ad5bceb85d3b1ab8c4b6905a5da3e))
* **python:** the to-do list records the live back-channel logout run ([34bca30](https://github.com/masksrb/masks/commit/34bca3006571aeba0ae8523ed1158ec603e5c14f))


### Refactoring

* **python:** the signed-in party is an Actor, the name masks itself uses ([ca4ca68](https://github.com/masksrb/masks/commit/ca4ca683c7f6ebe82197a8ae8a1f60e463eac252))

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
