# Changelog

## [1.0.0](https://github.com/masksrb/masks/compare/server-v0.1.0...server-v1.0.0) (2026-09-12)


### ⚠ BREAKING CHANGES

* **server:** the inviteActor mutation is gone. Callers move to createActor, whose email argument is no longer required.

### Features

* **client:** an app can act on a logout the issuer tells it about ([4d0b7f7](https://github.com/masksrb/masks/commit/4d0b7f77a74b0e416dda3e90413ad989a909f344))
* one palette across sign-in, the console and the docs ([20c5ee0](https://github.com/masksrb/masks/commit/20c5ee01274f6cba9f3d66b882a27236a6886830))
* **server:** a client hears about a sign-out it was part of ([a574959](https://github.com/masksrb/masks/commit/a57495961e1cbf70428ba98aebcea9c7aead6fd3))
* **server:** a client is edited and restored, and activity narrows to one subject ([bb24d0f](https://github.com/masksrb/masks/commit/bb24d0f7daf0818299e3fc3c29b8bb8212dff9a7))
* **server:** a client is told a subject of its own, and cannot correlate it ([8f65e3a](https://github.com/masksrb/masks/commit/8f65e3a91da32256c541165a118d62b7eebd4570))
* **server:** a client pushes its authorization request before sending anybody ([ca1c602](https://github.com/masksrb/masks/commit/ca1c602c785a8bc42cd68963e6606ae90aea83d6))
* **server:** a console shows the tokens still outstanding, and revokes them ([a7c7fef](https://github.com/masksrb/masks/commit/a7c7fefb91be8aa358404d32acc8e7ee12cf7a95))
* **server:** a console shows what somebody has allowed in and connected ([cb59f65](https://github.com/masksrb/masks/commit/cb59f654060210785bf2aecfc6c1c52e2e44bf99))
* **server:** a device with no browser is signed in from a phone ([809864b](https://github.com/masksrb/masks/commit/809864b5e77c927411af02c56199e5b2c7a2058f))
* **server:** a device you already signed out stops offering the button ([852236c](https://github.com/masksrb/masks/commit/852236ca68fb0c8a6ecba2e4ec54b7b9f68680e1))
* **server:** a first boot fetches authenticator metadata rather than seeding names ([f5fb0d6](https://github.com/masksrb/masks/commit/f5fb0d600181d984f3d7e4e868577bfb94339939))
* **server:** a namespace can be released from the console ([87f68cc](https://github.com/masksrb/masks/commit/87f68ccb84a206c538cb386c81b762b2f366e967))
* **server:** a namespace is a grant, so an app can grow its own scopes ([0875440](https://github.com/masksrb/masks/commit/0875440bc37d8372395b3e206a053184aae50ec8))
* **server:** a namespace is claimed when a handshake is approved ([1161b35](https://github.com/masksrb/masks/commit/1161b3571a383936c3c9a772606a4a762f23f921))
* **server:** a new database is seeded with the authenticators masks ships ([e882c70](https://github.com/masksrb/masks/commit/e882c70c8607c5cc844a5af51bae2f783ce7132b))
* **server:** a provider is set up from the console, not a rails console ([85471fc](https://github.com/masksrb/masks/commit/85471fc9c3affb27bae870e220662adf60872b9f))
* **server:** a scope is named in a word or two, not a sentence ([51ec7c8](https://github.com/masksrb/masks/commit/51ec7c8c454996abfd9760c3d6b18200a4932fb8))
* **server:** a sign-in shows what the server is doing at every step ([c4c2660](https://github.com/masksrb/masks/commit/c4c26600bfee79bc0108985657de24b1db26eb40))
* **server:** a tenant holds its own mailer, and changes it without a restart ([3e29b9a](https://github.com/masksrb/masks/commit/3e29b9a6363b08665ef4d8029c3c362d9c760976))
* **server:** a tenant you pin serves every hostname ([5915963](https://github.com/masksrb/masks/commit/59159634e6640f0a17f4c8e9c803dfe3f52bbcca))
* **server:** a token is held to a key its client never sends ([0c97ab9](https://github.com/masksrb/masks/commit/0c97ab92e315d2f88243e85493be340ec9ea5335))
* **server:** an account is named by a nickname, an address, or either ([65419b2](https://github.com/masksrb/masks/commit/65419b2caf1ffffcb5d95e1407767b25e0945c55))
* **server:** an account is told by email what happens to it ([7d3f0dc](https://github.com/masksrb/masks/commit/7d3f0dc5089719e0f6f541a6f7e16d85da0b974e))
* **server:** an account reads as panels, and says what wants doing first ([effb20e](https://github.com/masksrb/masks/commit/effb20e45b17bdd6d486523f152ecccbbb1ef941))
* **server:** an avatar is uploaded through the manage API ([6ef4db4](https://github.com/masksrb/masks/commit/6ef4db43e24b3cf96293fdcdbff78657c872cf6f))
* **server:** an empty instance goes to setup instead of describing itself ([028c186](https://github.com/masksrb/masks/commit/028c1861567743915b8c4ffb236b8633a913a3da))
* **server:** an empty instance says it is empty ([160b788](https://github.com/masksrb/masks/commit/160b788ec00d3a76caeef0423e0d3e82860d1190))
* **server:** authenticator metadata is refreshed on a schedule, not by hand ([9631c53](https://github.com/masksrb/masks/commit/9631c53eb2f4988fa6bb5717bc50fb4a9779678f))
* **server:** configuration asks for the name and the mailer, and nothing else ([83ac6a8](https://github.com/masksrb/masks/commit/83ac6a83e9ac9bdb9f4c0febb622361e3ccac3c9))
* **server:** configuration is the installation's name and the URL it answers on ([0496442](https://github.com/masksrb/masks/commit/04964428754fc0a672f712d28c18e2a3c2b35a44))
* **server:** create actors from /manage, with or without a password ([59357e2](https://github.com/masksrb/masks/commit/59357e2c4b548204b378dcf0f39259b208660e34))
* **server:** devices have a page of their own, and activity narrows to one ([20e25dc](https://github.com/masksrb/masks/commit/20e25dc158150f63214f98d92b6b587f0d08553e))
* **server:** devices, so a session belongs to a browser you can name, trust or shut out ([09a9d4e](https://github.com/masksrb/masks/commit/09a9d4ee67d0b38b0779751ef368cfe6c89bb4c9))
* **server:** dynamic registration can be turned off ([079c53e](https://github.com/masksrb/masks/commit/079c53e482ed7519f129996460c028afa4a39c33))
* **server:** every consequential act is written down ([6d834aa](https://github.com/masksrb/masks/commit/6d834aa1a98396cf5f34449892bc29f3cf526488))
* **server:** five surfaces, so a grant never looks like a sign-in ([84123cb](https://github.com/masksrb/masks/commit/84123cb3714b4ab3f39705c0292d8799e1889dd7))
* **server:** mail goes over SMTP, and is styled where it is read ([e5416c3](https://github.com/masksrb/masks/commit/e5416c39a6d71a5a8c5c08dedd017da65919309c))
* **server:** one visual language across sign-in, /account and the console ([9127584](https://github.com/masksrb/masks/commit/912758443bb8eb61cfa2c780ed0de5484d272645))
* **server:** people and clients page past the first fifty ([54336b3](https://github.com/masksrb/masks/commit/54336b33b564a34b9b717f54bf21f6b8c3215a23))
* **server:** people narrow to the invited and the privileged, and every namespace is listed ([49805de](https://github.com/masksrb/masks/commit/49805de0c866d4394a1e55c08901d39b5cce2933))
* **server:** people, avatars, and one page instead of three ([e3d544f](https://github.com/masksrb/masks/commit/e3d544f04e338ec145789bbb828c3c299ceccf94))
* **server:** setting up confirms the password before it creates the owner ([6c604ea](https://github.com/masksrb/masks/commit/6c604ea303e7727ab98a2c8cc9c34702136d9695))
* **server:** somebody signs in with a provider, not only connects one ([a4ead6b](https://github.com/masksrb/masks/commit/a4ead6b006e0a1859993e5c2a780043a68aede0b))
* **server:** the account page follows the reference it was given ([43488d2](https://github.com/masksrb/masks/commit/43488d2af95c89742c7bcadd041f65c5eb5444ee))
* **server:** the account page reads like an account page ([186247f](https://github.com/masksrb/masks/commit/186247f7a273139838dc507608fabc8f04953719))
* **server:** the account, mail and refusal screens read from a locale file ([0d1b8b6](https://github.com/masksrb/masks/commit/0d1b8b614bf0c1e901c4e86b7e0ef26ae6805f91))
* **server:** the first-run screen takes a name as well as a nickname ([1e36707](https://github.com/masksrb/masks/commit/1e36707e8041492e5a04fe7fafa77e60f3d2820b))
* **server:** the last tab asks what this installation is called, and what apps may register for ([4dfa926](https://github.com/masksrb/masks/commit/4dfa926f6d3604caff112c79ff60d0ad8b99c22a))
* **server:** the login machine speaks the reader's language ([f7a7587](https://github.com/masksrb/masks/commit/f7a75875cd8c03e10fd572ff9f38be1a809c3e22))
* **server:** the scopes on offer include the ones this server publishes ([e473a45](https://github.com/masksrb/masks/commit/e473a4577b0948804924cdef9e73a6cfbae064d2))
* **server:** the sign-in screens are grey, and setup earns its colour ([ad7dce2](https://github.com/masksrb/masks/commit/ad7dce222b15bb9d1515fbf15ef4dcb38c2101f6))
* **server:** the source reloads when it runs in a container ([2e7480a](https://github.com/masksrb/masks/commit/2e7480a88abbaa2019171aee076dfde2b43e9702))
* **server:** the whole dev stack runs from one command and one compose file ([fe14d51](https://github.com/masksrb/masks/commit/fe14d51e5a8a07439dd6b59bbab15b78f0210a87))
* the server is published as a container image ([16630a8](https://github.com/masksrb/masks/commit/16630a8e71c5244e404d4f7d7a3a8dc016117eb2))


### Fixes

* **dev:** background jobs run on the host, not only inside the container ([24369d2](https://github.com/masksrb/masks/commit/24369d2a59b96efbbaa598f9b6b28a5b2ea60a18))
* **server:** a client pushing over basic auth need not repeat its id ([9750224](https://github.com/masksrb/masks/commit/9750224fd0be3c227e154f019282970e7821276b))
* **server:** a client stops reading tokens by declaring somebody else's resource ([8b9b877](https://github.com/masksrb/masks/commit/8b9b877c4d91a2673dd11a12f63ca4abb2f68681))
* **server:** a job invoked in process is not refused for having no envelope ([2510b3e](https://github.com/masksrb/masks/commit/2510b3e76641378b4673117cff9f19bfab26e82b))
* **server:** a job reads its tenant from its own envelope, not from the thread ([9fa8dcb](https://github.com/masksrb/masks/commit/9fa8dcb16738ae9cc946f6063bd5a97b4875495d))
* **server:** a logout hint ends only the session of the person it names ([d84a6b4](https://github.com/masksrb/masks/commit/d84a6b428be546f38aacc5d70780c2e405d65987))
* **server:** a logout no client ever answered is written down ([b26defe](https://github.com/masksrb/masks/commit/b26defe89f58d7fe57822895dcccfd95a275f263))
* **server:** a one time password is spent by the sign-in that used it ([9555716](https://github.com/masksrb/masks/commit/9555716aa307ba885824bfad284b0d616a93ecdb))
* **server:** a pushed request names its client, whatever it authenticated with ([0ae893a](https://github.com/masksrb/masks/commit/0ae893af99bd78d3c296a82a5e87537b4b91f463))
* **server:** a re-authentication names the person who just proved themselves ([4c87358](https://github.com/masksrb/masks/commit/4c87358ca2a6caf209403ab19750a0acb9e84762))
* **server:** a replayed refresh token takes its whole family down ([02f08ca](https://github.com/masksrb/masks/commit/02f08caa8ec68c4e419dfaa8132a192f2b40ab95))
* **server:** a second factor proved by one account stops satisfying another's ([74f18fd](https://github.com/masksrb/masks/commit/74f18fdaf6325a69193b3b55ac68c03190fa3c03))
* **server:** a self-registered client is not called inside the network ([dcb510c](https://github.com/masksrb/masks/commit/dcb510cbe3c168efce8577bc25e786146db2033c))
* **server:** a switch refuses a database role that sees past row-level security ([40d9668](https://github.com/masksrb/masks/commit/40d96686fbb19b37ffbbdaa75bc33dd6da28e13d))
* **server:** a tenant is named exactly what it was declared ([d3f3b9f](https://github.com/masksrb/masks/commit/d3f3b9f3ebb5d2ce4383af3a722e1fb55476fb6d))
* **server:** a token endpoint stops naming resources the authorization never carried ([0d66ee4](https://github.com/masksrb/masks/commit/0d66ee458a794cbe09a8c43a3b8405591c8f7e86))
* **server:** an address belongs to one account ([3864bf0](https://github.com/masksrb/masks/commit/3864bf056bb0cf367c3b4c5ba5a94bd9309b7749))
* **server:** an allowed domain is one the provider actually confirmed ([121ce96](https://github.com/masksrb/masks/commit/121ce96c40fe5dbe2d64410239a920fcac8f6c23))
* **server:** an upstream identity reaches an account only by proving it ([481073c](https://github.com/masksrb/masks/commit/481073ce9c99ae98b20dff8eb55f51fc7ac178f0))
* **server:** approving an application takes a scope of its own ([7adc1bc](https://github.com/masksrb/masks/commit/7adc1bc5d45b26f71ba70671e0906b2af5cc7db6))
* **server:** containers sharing a node_modules volume install one at a time ([446623a](https://github.com/masksrb/masks/commit/446623a0c5ba1e76de7512240ad1918357ba682e))
* **server:** the activity log pages by cursor, not by timestamp ([2c8d7a7](https://github.com/masksrb/masks/commit/2c8d7a7c8ec5bec7a9a2f7e701efcf69df8e5873))
* **server:** the console is Helvetica, and a badge grows to fit its label ([6e70fd7](https://github.com/masksrb/masks/commit/6e70fd7f9faf907aa9cf9bca34976b3340de4440))
* **server:** the first-run heading gets room under it ([f31fdc0](https://github.com/masksrb/masks/commit/f31fdc0cdf245d5a00f6b1dd4db849df86c2b377))
* **server:** the image builds again, and a derived avatar is not shared ([a919e5a](https://github.com/masksrb/masks/commit/a919e5aaf2da75bcb7e9c7c3b3629f9bc4f87546))
* **server:** the manage API passed a value-returning callback to forEach ([b38cef4](https://github.com/masksrb/masks/commit/b38cef4ea8339b7df6aa6dda7735ef46727269b5))
* **server:** the origin is configuration, and approval decides where a client lives ([b19a66c](https://github.com/masksrb/masks/commit/b19a66c3d5b1f2941ecc2df8c2e917f39ccdbb4d))
* the test tasks live where every other rake task does ([003faaf](https://github.com/masksrb/masks/commit/003faaff8a85b0180ffa9102d1c835a36205a6f6))


### Performance

* **server:** the suite stops generating an RSA key it never reads ([6b65fc2](https://github.com/masksrb/masks/commit/6b65fc25bc21f734ba96856b3cd3b3cae10ac089))


### Documentation

* READMEs that match the code, and a server one that is not the scaffold ([e0148e1](https://github.com/masksrb/masks/commit/e0148e14e0092731bcd095bc0fc22a1589c3acc0))
* references are generated from the code that defines them ([ba74550](https://github.com/masksrb/masks/commit/ba745501e651b797948e5abd5640a1825616100c))


### Refactoring

* comments are gone; the code says what it does ([0fc8e6a](https://github.com/masksrb/masks/commit/0fc8e6a4692e3f09831514b6d167c3e23d7db419))
* **db:** one migration creates the schema ([ad0685c](https://github.com/masksrb/masks/commit/ad0685c861990d21cd0f5279529d8ded65521d9a))
* every suite is named for what it proves, under one test directory ([315b371](https://github.com/masksrb/masks/commit/315b371e64baa4441014669744a61c88341d27c7))
* one command owns the repo, and CI runs in the order it should ([161f823](https://github.com/masksrb/masks/commit/161f823ac64dd40bf305ddb066803a00f9ed97ea))
* rename the example tenant from jons to demo ([aef32a6](https://github.com/masksrb/masks/commit/aef32a670b4b3c696089c07bf15103e1d981eb00))
* **server:** a lines field seeds its draft without tracking the prop ([fcc86c1](https://github.com/masksrb/masks/commit/fcc86c1957537579b75d0c6f719358ce6e8eb3aa))
* **server:** a tenant is entered once, at the edge, and carried the rest of the way ([1a7618b](https://github.com/masksrb/masks/commit/1a7618b01814340a0a757a2f6efa7eb3a8215a61))
* **server:** the backup code task retires, as the manage API generates them ([bf34ebe](https://github.com/masksrb/masks/commit/bf34ebeebbd16247d89aa849f2ca4c51737926b4))
* **server:** the three new grants stop repeating themselves ([8e16317](https://github.com/masksrb/masks/commit/8e163172b6c57645f307a036cf858838bb8c4fab))
