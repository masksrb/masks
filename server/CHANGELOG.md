# Changelog

## [1.0.0](https://github.com/masksrb/masks/compare/server-v0.1.0...server-v1.0.0) (2026-09-07)


### ⚠ BREAKING CHANGES

* **server:** the inviteActor mutation is gone. Callers move to createActor, whose email argument is no longer required.

### Features

* **client:** an app can act on a logout the issuer tells it about ([c103acb](https://github.com/masksrb/masks/commit/c103acbb27d8c96ad71439af2b6eba03024fbba0))
* one palette across sign-in, the console and the docs ([7350627](https://github.com/masksrb/masks/commit/7350627fa27b92e9dfce57d2d55a66cb40306cfe))
* **server:** a client hears about a sign-out it was part of ([d15a619](https://github.com/masksrb/masks/commit/d15a619fd54a03fe1080e7046da02c8e51e92128))
* **server:** a client is edited and restored, and activity narrows to one subject ([8f59dc6](https://github.com/masksrb/masks/commit/8f59dc642b5c8f2f1a65d8fc1ab829a3e82b4727))
* **server:** a client is told a subject of its own, and cannot correlate it ([391678d](https://github.com/masksrb/masks/commit/391678dd14a2f6a46577f612c4dddb85e5c35486))
* **server:** a client pushes its authorization request before sending anybody ([40c3d62](https://github.com/masksrb/masks/commit/40c3d625f75782835a97129afd10d34338e0f0fe))
* **server:** a console shows the tokens still outstanding, and revokes them ([f42467b](https://github.com/masksrb/masks/commit/f42467bc31158b89e8b09ed3af661baa937c67a6))
* **server:** a console shows what somebody has allowed in and connected ([354f7ab](https://github.com/masksrb/masks/commit/354f7ab63c3b83cc27dac209cf85f7b09b585aeb))
* **server:** a device with no browser is signed in from a phone ([cdef748](https://github.com/masksrb/masks/commit/cdef74817fabd4b4a19f22fcd696bca3d2ea1833))
* **server:** a device you already signed out stops offering the button ([674544c](https://github.com/masksrb/masks/commit/674544c6eac94871b287c5977283739ab2f4ae50))
* **server:** a first boot fetches authenticator metadata rather than seeding names ([98c17a8](https://github.com/masksrb/masks/commit/98c17a814f07604293c9906ff0bb023608085231))
* **server:** a namespace can be released from the console ([c4c8ecd](https://github.com/masksrb/masks/commit/c4c8ecdd42175292e77971841c996998ff748dd9))
* **server:** a namespace is a grant, so an app can grow its own scopes ([4e816e4](https://github.com/masksrb/masks/commit/4e816e4456de9cc05601b8eaa03773788e3178bb))
* **server:** a namespace is claimed when a handshake is approved ([a48b4e8](https://github.com/masksrb/masks/commit/a48b4e812294b5e98a3f467fa867e8ef94198e7d))
* **server:** a new database is seeded with the authenticators masks ships ([0ae0903](https://github.com/masksrb/masks/commit/0ae0903b68d0d12bf911a3502253ad69236e44e6))
* **server:** a provider is set up from the console, not a rails console ([ba065fa](https://github.com/masksrb/masks/commit/ba065facc32eec3f962e912c379761962d46a03a))
* **server:** a scope is named in a word or two, not a sentence ([59c2a36](https://github.com/masksrb/masks/commit/59c2a36c12c8a9fdf548f3706f895ba3d7668f5b))
* **server:** a tenant you pin serves every hostname ([143c73e](https://github.com/masksrb/masks/commit/143c73e5e14beac642b5c135cba31062f3dc16bc))
* **server:** a token is held to a key its client never sends ([b4d56f5](https://github.com/masksrb/masks/commit/b4d56f5583fb8472d8c01f1a2808b7a0078ad6f0))
* **server:** an avatar is uploaded through the manage API ([5a33c4d](https://github.com/masksrb/masks/commit/5a33c4ddc3d356e119e91bc8a1a9d8e31ec0d6e1))
* **server:** an empty instance goes to setup instead of describing itself ([c3302e0](https://github.com/masksrb/masks/commit/c3302e08cc1136ee5153da1362f3d6a57281613e))
* **server:** an empty instance says it is empty ([082c4fb](https://github.com/masksrb/masks/commit/082c4fb9a9a97265a28ca84dcf564866825ca8c7))
* **server:** authenticator metadata is refreshed on a schedule, not by hand ([202e424](https://github.com/masksrb/masks/commit/202e424b6e38d879f75eb1aaa5ff5a17ae7a3b7c))
* **server:** create actors from /manage, with or without a password ([18ae9cd](https://github.com/masksrb/masks/commit/18ae9cd04f8b140f6e047ee0d9f2b327e9519063))
* **server:** devices have a page of their own, and activity narrows to one ([10a9fec](https://github.com/masksrb/masks/commit/10a9fece7832a635b2e586e7d38bcda86753fc3b))
* **server:** devices, so a session belongs to a browser you can name, trust or shut out ([5ef865a](https://github.com/masksrb/masks/commit/5ef865a548836e023b84d38daba8e60b94591bfd))
* **server:** every consequential act is written down ([eb0fa83](https://github.com/masksrb/masks/commit/eb0fa83c4fbb206f29e55b21725a510c86d78d69))
* **server:** five surfaces, so a grant never looks like a sign-in ([b8de993](https://github.com/masksrb/masks/commit/b8de9935d9dd64cfcc4dd81885a3eeec035bf649))
* **server:** mail goes over SMTP, and is styled where it is read ([6ecd1f7](https://github.com/masksrb/masks/commit/6ecd1f7b7085e526c5b51180543f189493f32855))
* **server:** one visual language across sign-in, /account and the console ([85bfe24](https://github.com/masksrb/masks/commit/85bfe2462788a301635a6c1ddf0886717cc878e5))
* **server:** people and clients page past the first fifty ([39c1223](https://github.com/masksrb/masks/commit/39c1223ed59ac5d74d2608d3c44523aad6e6f581))
* **server:** people narrow to the invited and the privileged, and every namespace is listed ([322a892](https://github.com/masksrb/masks/commit/322a892feba2577843a9217d2640cd6d60a10c31))
* **server:** people, avatars, and one page instead of three ([d50c444](https://github.com/masksrb/masks/commit/d50c4440812fc1c3a92e926ff6d533b9a69dae2a))
* **server:** somebody signs in with a provider, not only connects one ([b39490e](https://github.com/masksrb/masks/commit/b39490e93af1a7d85d613b91dfe9def501874f1c))
* **server:** the account, mail and refusal screens read from a locale file ([8e8b38b](https://github.com/masksrb/masks/commit/8e8b38ba76429b4705ed4caa9f3e3d6e78a1f5ff))
* **server:** the login machine speaks the reader's language ([4d5a885](https://github.com/masksrb/masks/commit/4d5a885427814c7fa16b65a50063285e79f89fdc))
* **server:** the scopes on offer include the ones this server publishes ([15f7d01](https://github.com/masksrb/masks/commit/15f7d0117d25a5d6db69c9df54048b214f769989))
* **server:** the sign-in screens are grey, and setup earns its colour ([f00935f](https://github.com/masksrb/masks/commit/f00935fe5e6afdfa3272adc7e57fe90e7f426740))
* **server:** the source reloads when it runs in a container ([68e01e1](https://github.com/masksrb/masks/commit/68e01e10bf75d38ea746e62b5d4e6e5716d3a137))
* the server is published as a container image ([5ea221e](https://github.com/masksrb/masks/commit/5ea221e8a3b445e2fcbd5d01cd968cfbba20ef42))


### Fixes

* **dev:** background jobs run on the host, not only inside the container ([ef4266e](https://github.com/masksrb/masks/commit/ef4266ea1a6502457b85e8fb49752813ab1539a3))
* **server:** a client pushing over basic auth need not repeat its id ([057701e](https://github.com/masksrb/masks/commit/057701ed58b77312930e187590885302fa8596ae))
* **server:** a job invoked in process is not refused for having no envelope ([ecf1db5](https://github.com/masksrb/masks/commit/ecf1db51b07d451c38ca69946efa013930d2bd0e))
* **server:** a job reads its tenant from its own envelope, not from the thread ([e166811](https://github.com/masksrb/masks/commit/e16681182a0bab4b69f7abcbfa92d61bebe4ca5f))
* **server:** a logout no client ever answered is written down ([b52994a](https://github.com/masksrb/masks/commit/b52994a7aca9e6a235137bd0c65b3f794e6c8fbe))
* **server:** a pushed request names its client, whatever it authenticated with ([15ffc49](https://github.com/masksrb/masks/commit/15ffc4914d323a2a6d069fe99821713237fd835f))
* **server:** a replayed refresh token takes its whole family down ([c641c32](https://github.com/masksrb/masks/commit/c641c323140433e4fc5fa99d68319292f9fb5408))
* **server:** a self-registered client is not called inside the network ([dba62b5](https://github.com/masksrb/masks/commit/dba62b5cdef6f8e2b8a2c81854d4d093bd9bdd64))
* **server:** a switch refuses a database role that sees past row-level security ([423c93f](https://github.com/masksrb/masks/commit/423c93fffeaca9f5769e08c1591387609d7da487))
* **server:** an allowed domain is one the provider actually confirmed ([39624c5](https://github.com/masksrb/masks/commit/39624c5da263c1c402b4920fadaf003d32a655ed))
* **server:** approving an application takes a scope of its own ([8f9b394](https://github.com/masksrb/masks/commit/8f9b394a38ba7f686e70c517f84911d1d56fc9b9))
* **server:** containers sharing a node_modules volume install one at a time ([911fbb2](https://github.com/masksrb/masks/commit/911fbb273a14eff13435895cd03be226ee61c901))
* **server:** the activity log pages by cursor, not by timestamp ([942fe1a](https://github.com/masksrb/masks/commit/942fe1ac4bfaefc5a1283715cbbdcd31096ac538))
* **server:** the console is Helvetica, and a badge grows to fit its label ([192eef4](https://github.com/masksrb/masks/commit/192eef4ea6e38ed454c6e893b15672c081a1ba76))
* **server:** the image builds again, and a derived avatar is not shared ([d82e968](https://github.com/masksrb/masks/commit/d82e9683566c5157030a4183c1e39d8735244ed8))
* **server:** the manage API passed a value-returning callback to forEach ([8868766](https://github.com/masksrb/masks/commit/8868766228f05c494c27086c01d52c38a4e6501b))
* **server:** the origin is configuration, and approval decides where a client lives ([f878af0](https://github.com/masksrb/masks/commit/f878af09a63e7ec4a7dd23ab756c74ddf63b3beb))
* **server:** the Rails master key leaves the repository and is ignored from now on ([d5ae0d8](https://github.com/masksrb/masks/commit/d5ae0d896d470a38c08803c9bd55c8cf1fa7fd3f))


### Performance

* **server:** the suite stops generating an RSA key it never reads ([82e4723](https://github.com/masksrb/masks/commit/82e4723fa5fd6aba649328169110c03bbc0a17a0))


### Documentation

* READMEs that match the code, and a server one that is not the scaffold ([2b1fc4f](https://github.com/masksrb/masks/commit/2b1fc4f8f2bbb32e4d2381f38f3f7ef446e8ee8f))
* references are generated from the code that defines them ([1ac0166](https://github.com/masksrb/masks/commit/1ac01668fcf2d69547f242982e922ddad92d89ed))


### Refactoring

* comments are gone; the code says what it does ([6857ff2](https://github.com/masksrb/masks/commit/6857ff20f1fbeee1471ff5ca07a591e0489066fa))
* rename the example tenant from jons to demo ([833a48b](https://github.com/masksrb/masks/commit/833a48bcdd03541bacede41ad077c3c8077467d6))
* **server:** a lines field seeds its draft without tracking the prop ([645c89f](https://github.com/masksrb/masks/commit/645c89ffa7df49747dfdacc50c75dcf37bdcfe00))
* **server:** a tenant is entered once, at the edge, and carried the rest of the way ([737c0e6](https://github.com/masksrb/masks/commit/737c0e65aa8370fae112f5dd8d93f4a2d4508cd1))
* **server:** the backup code task retires, as the manage API generates them ([982d172](https://github.com/masksrb/masks/commit/982d17220204b167b3f8bb9e2d0a7c5a0b6816bb))
* **server:** the three new grants stop repeating themselves ([e4ac71a](https://github.com/masksrb/masks/commit/e4ac71a860bff96c90a12891c2aed985fdfdfbaa))
