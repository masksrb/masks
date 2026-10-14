# Changelog

## [0.9.0](https://github.com/masksrb/masks/compare/masks-server-v0.8.0...masks-server-v0.9.0) (2026-10-14)


### Features

* **engine:** a page on another site reads discovery, the keys, and the token, revocation, userinfo, and avatar answers, so a site with no server can sign people in ([ff4a0f0](https://github.com/masksrb/masks/commit/ff4a0f01735dfab8fb13758d782f4b49a8e2d911))


### Fixes

* **client:** signing out of masks returns to /auth/logout/return, which the handshake registers as the app's post-logout address ([d1dbc05](https://github.com/masksrb/masks/commit/d1dbc05e6bcbe41a4143b1efde901495dd6dbcae))
* **engine:** a client that declares no scope follows the registration setting, so with registration on it may ask for a resource's scopes ([bfbd156](https://github.com/masksrb/masks/commit/bfbd15606ebc77babed0d429b303a1caac459d15))
* **engine:** a handshake registers only the post-logout address it names, and keeps its return_to apart, so a new return_to is still asked about ([47a8988](https://github.com/masksrb/masks/commit/47a898874ee2c00f9763a57624cc3cb207a7e48f))
* **engine:** a loopback redirect_uri matches on any port, so Claude Code and other native apps can sign in ([f5038e3](https://github.com/masksrb/masks/commit/f5038e3e9855d6ed7053927381e0de877110d6fe))
* **engine:** a machine signs in to masks mounted under a path, since its DPoP proof is checked against the address it posted to ([d919827](https://github.com/masksrb/masks/commit/d9198275b6f226e56ee72ce55766a1ae076baf20))
* **engine:** a refused token is described in masks' own words, not the JWT library's ([dae249d](https://github.com/masksrb/masks/commit/dae249d348c65e83bf96f680746d60ba4642c58d))
* **engine:** a request that carries no token is asked for one with no error code ([f8b464d](https://github.com/masksrb/masks/commit/f8b464d191f6b9f6ddfe412cc8708aea9dea7927))
* **engine:** auth_time is the moment of the first factor in every ID token a session gives, and signing in again moves it forward ([c6f7dc0](https://github.com/masksrb/masks/commit/c6f7dc026148adaa9128ba9bb72910e570274ab5))
* **engine:** the activity titles for adding, deleting, suspending, and restoring someone say Account, like the rest of the group ([71a1c09](https://github.com/masksrb/masks/commit/71a1c0905635a9b924527b9c98ab5abd0bdd30be))
* **engine:** the boot errors for MASKS_NAMED_BY and MASKS_DYNAMIC_REGISTRATION say an unset value leaves the choice to /manage, and SCIM's documentationUri points at the provisioning guide ([fbe68ca](https://github.com/masksrb/masks/commit/fbe68cae7a4263da837ae7c8f226001c6dc1d903))
* **engine:** the install generator says a role that bypasses row-level security fails every request that needs a tenant, since masks checks the role then and not at boot ([46d894e](https://github.com/masksrb/masks/commit/46d894e1ac69a3b5db79a8e04ea4a54e2d5aed0e))


### Documentation

* comments and pages no longer claim what masks stopped doing ([e0b1ba0](https://github.com/masksrb/masks/commit/e0b1ba0b71ccae8683b605f9442ee16c4afb5dd4))
* the Manage API page holds the schema explorer, and /reference/explorer redirects to it ([9739b00](https://github.com/masksrb/masks/commit/9739b0047d187c943bb784124d924ec4c17233f4))


### Refactoring

* **engine:** account and manage locale keys, the profile icon, and the signup name field are named for actors and members ([3dbeec9](https://github.com/masksrb/masks/commit/3dbeec95c0ee8446f230c8ec48da8e2c44c22c54))
* **engine:** the signed-in card is the actor partial and component, and the login JSON carries it as actor.card ([07892cb](https://github.com/masksrb/masks/commit/07892cb95ec16c8b65acee258938b18612830234))

## [0.8.0](https://github.com/masksrb/masks/compare/masks-server-v0.7.0...masks-server-v0.8.0) (2026-10-13)


### Features

* **server:** /manage, the sign-in pages, and the docs share one palette and one font stack ([17efe87](https://github.com/masksrb/masks/commit/17efe87c81c14d7541a37292bf58ba242836eca5))
* **server:** an actor's page splits into Profile, Access, Sign-in, and Activity, and the overview leads with what needs a manager ([b929c24](https://github.com/masksrb/masks/commit/b929c240db282bf4cad24827ef3517c703f09e06))
* **server:** an app asking to connect is described in plain words, with every technical detail one click away ([a2a0a57](https://github.com/masksrb/masks/commit/a2a0a570c8d66094a1344522fad40872eef96703))
* **server:** an app that holds a namespace enrolls its own machines, each registering its own key and signing in as itself with DPoP-bound client credentials ([0e909e0](https://github.com/masksrb/masks/commit/0e909e0708bac3f9201647c2cdb82c9c757b7b39))
* **server:** an app unenrolls a machine it enrolled, which archives the machine and revokes every token it holds ([8496c66](https://github.com/masksrb/masks/commit/8496c66f2b27ca28199bf843b5caed765de6831f))
* **server:** an organization's page in manage opens on its members and keeps sign-in, roles, activity, and its details on their own tabs ([69ac750](https://github.com/masksrb/masks/commit/69ac750c646bf307bf5730d0c25997fc4594870d))
* **server:** each provider has its own page with Setup, Sign-in, Clients, and Connected accounts, and adding one is a page of its own ([28cbe99](https://github.com/masksrb/masks/commit/28cbe994271aa27b63d0ecb32311c11cbe05c21c))
* **server:** the actors and clients lists mark each row with small icons, so a row is one name, one line of detail, and the columns that sort ([b360dbb](https://github.com/masksrb/masks/commit/b360dbbfc72a69036f03dda120dcd0a9f8a0a423))


### Fixes

* **engine:** the masks-server gem ships the Vite manifest its pages render from ([be2e1dc](https://github.com/masksrb/masks/commit/be2e1dcc1865920a84c9e4a7a6f586323ddee239))
* **server:** /manage says actor, client, activity, and changed everywhere, in every language it speaks ([9bfa00c](https://github.com/masksrb/masks/commit/9bfa00c0632e5bedfb8840f7cc47c1021bb05948))
* **server:** a client assertion, a DPoP proof, or a proof of work is good once across every process, kept in a replays table ([9cf14ac](https://github.com/masksrb/masks/commit/9cf14acca8ef79e0cbf826ed5c447eafb9690d6a))
* **server:** a client's keys are RSA of at least 2048 bits or EC on P-256, P-384, or P-521 ([13b49bd](https://github.com/masksrb/masks/commit/13b49bd9290c58f1ff64a7eab9d288e4606eeb10))
* **server:** a namespace claim refuses to nest under or around another resource's namespace ([350e8ef](https://github.com/masksrb/masks/commit/350e8efb59cddf8c45a4b0c1688c9241ab2e90ff))
* **server:** a public client enrolls no machines and unenrolls none ([314fa8c](https://github.com/masksrb/masks/commit/314fa8c85beef567f463edd35065096e9f610091))
* **server:** an archived client's tokens end with it, and an enrolled machine stays inside what its app gave it ([bb0092e](https://github.com/masksrb/masks/commit/bb0092e54cb4a36e04ce0e19120e8852bac2943b))
* **server:** archiving an app ends the tokens of every machine it enrolled, so introspection stops calling them active before they expire ([af4526d](https://github.com/masksrb/masks/commit/af4526d8405a6f5079ab89ca298c8ca478349e60))
* **server:** Spanish calls a manager a gestor everywhere, German blocks a device and suspends an actor with different verbs, and the words page names each concept in every language ([b607f7f](https://github.com/masksrb/masks/commit/b607f7fc18c0d865f45d60dd0fd517948bff9a8f))
* **server:** the activity log pages once, shortens IDs in an event's details, and names a machine enrollment request plainly ([9232fd0](https://github.com/masksrb/masks/commit/9232fd00074953f66ed00d0a1ee89578a990dc38))


### Refactoring

* expired replay ids are swept by the cleanup with everything else, and connecting an app shows the busy look every prompt uses ([ec28183](https://github.com/masksrb/masks/commit/ec281835043a31cf24d5620d2869b283208e64cd))
* **server:** /manage derives its surfaces from the shared palette, and --label folds into --brass ([c00d32b](https://github.com/masksrb/masks/commit/c00d32b821cc99b8cbc2903a7a4c0c08aa2770bd))

## [0.7.0](https://github.com/masksrb/masks/compare/masks-server-v0.6.0...masks-server-v0.7.0) (2026-10-11)


### Features

* **server:** a client's page splits into General, Access, Endpoints, and Usage, with one save for its links and one for its lifetimes ([ff16bc9](https://github.com/masksrb/masks/commit/ff16bc9b4de421b470ceefb6fb4abd7251633fa9))

## [0.6.0](https://github.com/masksrb/masks/compare/masks-server-v0.5.0...masks-server-v0.6.0) (2026-10-11)


### Features

* **server:** namespaces and signing keys are compact rows on General, with the rotation controls under the keys ([8cd4fdc](https://github.com/masksrb/masks/commit/8cd4fdc71b1aa836986c598000f59f54cc84a3f5))

## [0.5.0](https://github.com/masksrb/masks/compare/masks-server-v0.4.0...masks-server-v0.5.0) (2026-10-11)


### Features

* **engine:** a manager invites many people at once by pasting their addresses, and can put them all in groups ([2176a33](https://github.com/masksrb/masks/commit/2176a3332c0f8b2b3ccce650a9efe7ecc554859f))
* **engine:** a person names each of their passkeys from the account page ([b0af9d5](https://github.com/masksrb/masks/commit/b0af9d542d3e98721c4fb3ea7ce759b7b92e0357))
* **engine:** an owner can have signing keys rotate on a schedule, each new key published a day before it signs ([82ab614](https://github.com/masksrb/masks/commit/82ab6146722dabacc25f2bb30d5924d986a683a1))
* **engine:** an owner issues and revokes LDAP credentials and allows password-only binds from the console ([fb57bbd](https://github.com/masksrb/masks/commit/fb57bbdf07d262305a6762681f8fee925d2de443))
* **engine:** each tenant's encrypted columns use a key derived for that tenant alone ([f914595](https://github.com/masksrb/masks/commit/f914595fe8118244b951aca78a3a32e92d4e2d7b))
* **engine:** ldapwhoami confirms a person's password against bin/ldap, and LDAPS is tested end to end ([9877b92](https://github.com/masksrb/masks/commit/9877b926c62f8a9235aaf69ffddce5d01dfea7f5))
* **engine:** masks speaks French, Spanish, and German, chosen by the browser or by an app's ui_locales ([0109880](https://github.com/masksrb/masks/commit/0109880d65ce0273085320af7d04f02255471421))
* **engine:** older apps check passwords and read groups over a read-only LDAP directory that bin/ldap serves ([4ed1963](https://github.com/masksrb/masks/commit/4ed1963672ea66ec1d4b8a4232910b964d90a49c))
* **engine:** open signup asks the browser for a proof of work, so accounts cannot be made in bulk without paying for each one ([f881b86](https://github.com/masksrb/masks/commit/f881b8636e8ba10df8daff2a47a3e58c972c0f34))
* **engine:** SAML applications take part in single logout, both when they sign a person out and when the person signs out of masks ([b1ae96a](https://github.com/masksrb/masks/commit/b1ae96a4e8fe27f3b50ef0549ff2778f409e9238))
* **engine:** someone signing up chooses a passkey instead of a password, and the account needs nothing more ([f881b86](https://github.com/masksrb/masks/commit/f881b8636e8ba10df8daff2a47a3e58c972c0f34))
* **engine:** the web server serves LDAP, and an owner turns the directory on for their tenant in the console ([4a08277](https://github.com/masksrb/masks/commit/4a0827787f5dc594305b43a74b4c91ac03429de1))
* **server:** /metrics reports each tenant's accounts, sessions, and recent sign-ins to Prometheus, and invitations and group joins share one path ([f99ba58](https://github.com/masksrb/masks/commit/f99ba581e29734a22fe4f4f8d085e89499181c6d))
* **server:** a manager sets a SAML application's single logout URL in the console, or has it read from the application's metadata ([0fbc25b](https://github.com/masksrb/masks/commit/0fbc25b868d7f9417b0af3632f792249a679a248))
* **server:** every word the manage console shows comes from locale files, so the console can be translated ([de2446f](https://github.com/masksrb/masks/commit/de2446fa8e106819fe9660ad46914495913aafef))
* **server:** General holds groups and domains, and the console says templates, SMS, primary identifier, and auto-deletion ([315feba](https://github.com/masksrb/masks/commit/315febacff21195b0e270960cba7e276b86eb9c0))
* **server:** one Messages tab holds both the services that send mail and texts and what each email says ([8e85928](https://github.com/masksrb/masks/commit/8e85928aa4c5e7a6a7045d5b57d47465ac0ebb27))
* **server:** settings fit in six tabs, sign-in rules sit with the policies, and Provisioning and LDAP share a Directory page ([e38037f](https://github.com/masksrb/masks/commit/e38037f42150e2a725c33e64327ec62fbc1a0e71))
* **server:** the console shows how many people wait on a manager, and each page names itself and takes focus ([4b38e4d](https://github.com/masksrb/masks/commit/4b38e4d3a35f28de278c7a7e0234fc13065ed0b0))


### Fixes

* **engine:** a SAML logout read with HEAD takes its parameters from the query, as GET does, so only a POST reads them from the body ([928dcf7](https://github.com/masksrb/masks/commit/928dcf7c7e73da5bf3691cbebfdf9d9d2e7b3404))
* **engine:** an owner's accent color tints the sign-in pages ([e4c4242](https://github.com/masksrb/masks/commit/e4c42421c995aad61ca065d6df7a9cd66def0045))


### Performance

* **engine:** boot re-encrypts only the tenants not yet under their own key ([0176687](https://github.com/masksrb/masks/commit/01766875db87132955d1ab4b392c94eb73ea93e4))


### Refactoring

* **engine:** SAML messages an application sends are read and checked in one place ([6ee66af](https://github.com/masksrb/masks/commit/6ee66af7914ebdef999ffe3a79fdefbf76c6ec1c))
* **engine:** the services that send mail and texts are senders throughout, in the API, the events, and the database ([2f79202](https://github.com/masksrb/masks/commit/2f79202bbd0931df084e4dadc7c89d7a7e723cad))

## [0.4.0](https://github.com/masksrb/masks/compare/masks-server-v0.3.0...masks-server-v0.4.0) (2026-10-11)


### ⚠ BREAKING CHANGES

* **server:** the container image refuses to start without MASKS_MIGRATION_USER and MASKS_MIGRATION_PASSWORD, naming a role other than POSTGRES_USER that owns the schema. To move an existing database, run as a Postgres superuser, once, CREATE ROLE masks_owner WITH LOGIN PASSWORD '...' CREATEDB; and then in each of the primary, cache, and queue databases REASSIGN OWNED BY masks TO masks_owner; before starting the new image, which grants masks what it serves with.

### Features

* **engine:** a client_id that is the https URL of a client metadata document signs people in without registering first, as MCP clients do ([86dd5b6](https://github.com/masksrb/masks/commit/86dd5b61adf51f2dc0c294777eb2ed4af6fec5f7))
* **engine:** a consent remembers the authorization details a declared type allows, and a client's consents can expire ([bdfc149](https://github.com/masksrb/masks/commit/bdfc1496fe9f0a8df2aec8becb4b9637f23b200c))
* **engine:** a manager adds Grafana, Nextcloud, Gitea, Immich, and ten other self-hosted apps by picking one and entering its address ([02a8167](https://github.com/masksrb/masks/commit/02a81676d8c4f2b0b866882c391d21bec36e485f))
* **engine:** a person adds or removes an authenticator app and makes new backup codes from their account page ([e5d0623](https://github.com/masksrb/masks/commit/e5d0623c76623fa732974dd3aaa41754af4cbad4))
* **engine:** a person changes their own name, email address, and phone number, and sets a password, from their account page ([bc0d760](https://github.com/masksrb/masks/commit/bc0d76088e3b97f92b78a8156e6550c2f81a27d4))
* **engine:** a person downloads everything masks holds about them as a JSON file from their account page ([bc1b729](https://github.com/masksrb/masks/commit/bc1b72995a07ba43d518a10fbac2ae71fcba6c26))
* **engine:** an app with no sign-in of its own sits behind Caddy, Traefik, or nginx, which asks masks about each request ([382c650](https://github.com/masksrb/masks/commit/382c6507af96ad1dfd4566d1a84d450794944c28))
* **engine:** an owner rewords the subject and opening of the invitation, reset, confirmation, code, and approval emails, and adds a signature to every email ([eb74a02](https://github.com/masksrb/masks/commit/eb74a023994628f1a19cce6e12d822e17ef1181e))
* **engine:** an owner sets a logo and an accent color for sign-in and account pages from /manage ([5ac2972](https://github.com/masksrb/masks/commit/5ac297267b1eaad920d271c35ed3d8667014ff3c))
* **engine:** each client sets how long its access tokens and refresh tokens last ([3b91582](https://github.com/masksrb/masks/commit/3b915828c8ec2af788f87e06339d50a39b3097f5))
* **engine:** groups name sets of people, apps read them from a groups claim, and a client can admit only some groups ([e4569f6](https://github.com/masksrb/masks/commit/e4569f62124b7f16745252dc603455d0a1f9707a))
* **engine:** masks receives shared signals at /ssf/events, and a provider that revokes a session or disables an account signs that person out here ([7e627fe](https://github.com/masksrb/masks/commit/7e627fe62734c1356f56c1913f7ff45988044848))
* **engine:** MASKS_OUTBOUND_ALLOWED names private ranges masks may call, for apps on a private network such as a tailnet ([ed1a829](https://github.com/masksrb/masks/commit/ed1a82919ac7f74b9c43cee7381b04b6aae239a3))
* **engine:** rich authorization requests (RFC 9396) carry authorization_details from /authorize to the token, checked against types an approved client declares ([18dc29a](https://github.com/masksrb/masks/commit/18dc29a985b67b95e2e682b87a8a29829607a735))
* **engine:** someone who cannot use any second factor asks a manager for help, and a manager resets their second factors from /manage ([fb76944](https://github.com/masksrb/masks/commit/fb76944efd33b874229be91e52b6968a29c49249))
* **engine:** the account page opens each app a person may use, SAML applications that start their own sign-in included ([5518d6d](https://github.com/masksrb/masks/commit/5518d6d932e7d00edcfcf6258a61187f2e8a5837))
* **server:** MASKS_CONFIG declares apps, groups, and tenant settings in a file every boot applies ([689fc06](https://github.com/masksrb/masks/commit/689fc0648088f219ccdad0c4f2d3f330c8945f82))
* **server:** MASKS_RECOVER gets the only manager back into a locked account at boot ([d7e369d](https://github.com/masksrb/masks/commit/d7e369d913419a84653929fe11d55a8c07947210))
* **server:** the manage console reads its wording from locale files, through t() ([cac8d9c](https://github.com/masksrb/masks/commit/cac8d9caaf62a24f669e5fe2811f4b500d1c66e0))
* **server:** the master key can be rotated, and a server whose key cannot read the database refuses to start ([a03960f](https://github.com/masksrb/masks/commit/a03960fee563213b9f79aef9d2b1092ced454d8d))
* **server:** the server migrates as one Postgres role and serves as another, so the role answering requests cannot switch off row-level security ([e68df9c](https://github.com/masksrb/masks/commit/e68df9c3192f72be03070c99c241957c5d31ecb6))


### Fixes

* **engine:** a client that lists a grant type masks does not offer registers with the ones it does, so Claude connects again ([b85a2da](https://github.com/masksrb/masks/commit/b85a2da29bcde50c6f187e1d1557f8b15987e529))
* **engine:** a client that registers without naming scopes may ask for anything inside the tenant's ceiling ([e1ce171](https://github.com/masksrb/masks/commit/e1ce1715b09241cc29c7c2887ae63d97a386ed30))
* **engine:** a database connection takes up the borrower's tenant setting each time it leaves the pool ([e708efc](https://github.com/masksrb/masks/commit/e708efc58725e03e3a0666cf04c62fb7fefadbf6))
* **engine:** a mailed reset that first proves an account's address drops the passkeys and connections set up before it ([3a12071](https://github.com/masksrb/masks/commit/3a12071b8820b926a7b182437db76fa967b11e7b))
* **engine:** a manager who joins the console through the handshake gets its client id without new registration credentials ([c601377](https://github.com/masksrb/masks/commit/c6013770ac5c89f4634a1068e8e37ebd8a2063dd))
* **engine:** a phone number and an app's consent wait for the second factor ([e7710ed](https://github.com/masksrb/masks/commit/e7710ed0cda8db37d1022cbc656322d461ef6ae7))
* **engine:** a provider links an unactivated account only when an invitation waits for it, and answers only for domains the tenant proved ([5700d9b](https://github.com/masksrb/masks/commit/5700d9bafa4cb2c3255c7e3808179749ddeb9f63))
* **engine:** a public client cannot exchange an id token for an access token ([b363992](https://github.com/masksrb/masks/commit/b363992627af232fa2d1e3313a8c329ae0234e24))
* **engine:** a received security event token carries an issue time inside the replay memory ([f9fedd7](https://github.com/masksrb/masks/commit/f9fedd73ad900dc3d0d562e72c0df8a884e02b9d))
* **engine:** a redirect or post-logout redirect URI cannot use a scheme that runs a script, and post-logout URIs are checked at all ([f149eb4](https://github.com/masksrb/masks/commit/f149eb476445a7ca6600e5b9b07e5af9c5127ee9))
* **engine:** a refresh hands out only the scopes the person and the client still hold, and ends once their consent lapses ([b44a17b](https://github.com/masksrb/masks/commit/b44a17b283fa3fbcb6f35d7799273dab9022b13d))
* **engine:** a registration response, which carries a client secret and a registration token, is never cached ([39b6934](https://github.com/masksrb/masks/commit/39b6934e345aa0488a8aff607b843986411d8285))
* **engine:** a resource server describes only its own scopes on the consent screen, never masks' scopes ([9866b9d](https://github.com/masksrb/masks/commit/9866b9d13aed8bd6fd5a4759f97ce5c3fdc53689))
* **engine:** a scope ending in a colon counts as every manage scope it covers, so only an owner can hand it out ([cc957b1](https://github.com/masksrb/masks/commit/cc957b16e8a32f9b9896ce17c9b2375fc4dccb10))
* **engine:** a self-registered client cannot name resources, so it cannot have tokens addressed to another service ([39e186d](https://github.com/masksrb/masks/commit/39e186d38abc2c9a2b56483ef6c993d74d2c0905))
* **engine:** a signal stream stops following a person once they revoke the app or its tokens are spent ([8e27293](https://github.com/masksrb/masks/commit/8e27293309fc875d471365aecdea0c135824364f))
* **engine:** a token held to a key is exchanged only with a proof made with that key, and never for a scope the exchanging client may not hold ([df2f60c](https://github.com/masksrb/masks/commit/df2f60cadd93c107695b34c58dbbc6a8650563bd))
* **engine:** adding or removing a passkey, or turning sign-in codes on or off, asks for a sign-in within the last fifteen minutes ([e1dde90](https://github.com/masksrb/masks/commit/e1dde90a80c6030c0c1f6e4d6cacc1419f600962))
* **engine:** an outbound call has one deadline for connecting, headers, and body, and NAT64 and 6to4 addresses count as private ([b7e8168](https://github.com/masksrb/masks/commit/b7e81684d626495400766324ed28376423900ad4))
* **engine:** back-channel logout, every outbound post, and a tenant's SMTP server are held to the public-address check ([263d573](https://github.com/masksrb/masks/commit/263d573eb0244d02228b87a5402fb923470a7bf7))
* **engine:** claiming a tenant on first visit is limited per address and across the server ([34e8809](https://github.com/masksrb/masks/commit/34e8809abf93487c4adc3d6f24443ffdcfc1aea1))
* **engine:** images are decoded only by the PNG, JPEG, GIF, and WebP loaders ([2fc5461](https://github.com/masksrb/masks/commit/2fc54610be49c963c161c7457cba71557d41782d))
* **engine:** new apps named by a metadata document are limited per address and per tenant, and one nobody approved sends people back after sign-out only with an id_token_hint ([3e0bccb](https://github.com/masksrb/masks/commit/3e0bccb68242dd6462bd2ae12608bdd189809cdd))
* **engine:** posting to /login with only a session cookie keeps that session instead of minting a fresh one ([6b7f4a2](https://github.com/masksrb/masks/commit/6b7f4a260962b3e1d32c0d3a1f744c348e6fcbcc))
* **engine:** providers, SMS adapters, and resource metadata are called through Outbound, so a private address is refused there too ([20f8d2d](https://github.com/masksrb/masks/commit/20f8d2d9b2a18490128abfefa2cb76c74825a996))
* **engine:** revocation is rate limited per address, since every request checks a client secret ([17f808e](https://github.com/masksrb/masks/commit/17f808ee3ebfe8136f396d2c000617ce58bba16c))
* **engine:** signing out a device from the account page signs out only the account that asked ([6c86eaf](https://github.com/masksrb/masks/commit/6c86eaf76f82f7855f3d438d974bb104219c7019))
* **engine:** state joins a query the registered post_logout_redirect_uri already carries, instead of a second question mark breaking the address ([c639a6b](https://github.com/masksrb/masks/commit/c639a6b94379a775f035a09268dc5bb3bdc2cc20))
* **engine:** the daily cleanup deletes a chain of tokens only once nothing in it is live, so a live refresh token no longer stops the sweep for every tenant ([95c4f76](https://github.com/masksrb/masks/commit/95c4f7623d6848d9386434b3cb94f45e5a268f50))
* **engine:** the hourly domain check stops serving a custom host that falls inside the server's own domain ([71ae110](https://github.com/masksrb/masks/commit/71ae110218d8e00b7e77ecf448c8f12722deedee))
* **engine:** the login sends the browser only to a path on this server or an address it can safely follow ([82de7cb](https://github.com/masksrb/masks/commit/82de7cbf3741f7d9e9ded88cfe183222fc0ffeac))
* **engine:** the per-account sign-in limit counts the account, however its identifier is spelled ([c007079](https://github.com/masksrb/masks/commit/c007079a0fe4a6eb28665b570b436fb2ba4b3aae))
* **engine:** the provider's own forms check the form token whatever defaults the host app loads ([318cbc2](https://github.com/masksrb/masks/commit/318cbc2654ff09eacac41234b5ea32fe521d0cd5))
* **engine:** the support role helps a person without being able to take over their account ([b6a266e](https://github.com/masksrb/masks/commit/b6a266e55fb2a9ab9052ebadb2b8928e21b5c935))
* **server:** acr_values is read as a list of acceptable values, so a request that also accepts a password is not stepped up to a second factor ([ecaba6a](https://github.com/masksrb/masks/commit/ecaba6a97bc50f93c4ccbe89ab4df8681f21c04b))
* **server:** forwarding headers count only when a trusted proxy sent them, and MASKS_TRUSTED_PROXIES names the proxies to trust ([296e5dc](https://github.com/masksrb/masks/commit/296e5dce85c293362733a698ab557d31491a141d))


### Refactoring

* **engine:** deleting and downloading an account share one check for a fresh sign-in, and PKCE uses the client's one base64url digest ([6c08fcf](https://github.com/masksrb/masks/commit/6c08fcf709a08dbafd0a551801eaf43a4c325b75))
* **engine:** dynamic registration, registration updates, and client metadata documents read client metadata through one Client mapping ([cf0785d](https://github.com/masksrb/masks/commit/cf0785d86e16fdd7ca5dd51493695e01654d47d0))
* **engine:** methods nothing calls, the scaffold PWA views and Current.session go ([9d126ec](https://github.com/masksrb/masks/commit/9d126ec1c550950e8b4eec0ce58a0f0b474d4ffa))
* **engine:** one partial carries a tenant's email wording, one query loads it, and authorization_details narrow in one place ([1b2df29](https://github.com/masksrb/masks/commit/1b2df29380b2c2c8dc6b87d45d60b4ef23255b26))
* **server:** Thruster, capybara and the stale schema dumps go ([292b179](https://github.com/masksrb/masks/commit/292b1791e43ad4624fa743603206b8d178ebae36))

## [0.3.0](https://github.com/masksrb/masks/compare/masks-server-v0.2.0...masks-server-v0.3.0) (2026-09-28)


### ⚠ BREAKING CHANGES

* **server:** the icons are served at /masks-public/icon.svg, /masks-public/icon.png, and /masks-public/favicon.svg. SMTP settings apply to masks' own mailer, not ActionMailer::Base.
* **server:** job classes in recurring.yml and anything naming a provider class are now Masks::Server::*.

### Features

* **server:** a blocked device and a refused browser get a page that says what happened and what to do ([f68e767](https://github.com/masksrb/masks/commit/f68e767f1c2336051c3b99e1c68c59739dcd61c7))
* **server:** a client can require a second factor with acr_values or the claims parameter, and a sign-in that falls short is stepped up ([a6fd2fe](https://github.com/masksrb/masks/commit/a6fd2fed3d41d9ba4c79cb878a17fd8fd08f37a8))
* **server:** a customer's directory manages organization roles through SCIM groups ([edcc25a](https://github.com/masksrb/masks/commit/edcc25afa0fa9f78f8ddf7e75b656d3836cd2fa6))
* **server:** a passkey on the second factor screen trusts the device when asked to, and an account holding a passkey alone is offered the trust box ([e079aa2](https://github.com/masksrb/masks/commit/e079aa28a8fff0f9152ed610b45177576e46fd05))
* **server:** a person added to an organization is emailed where to accept it, an invitation names the organization and role, and a changed role or removal arrives as a notice they can turn off ([8786090](https://github.com/masksrb/masks/commit/87860907ddb26568a7c4d810b9de8b0a4e774e50))
* **server:** a public app that is already approved and allowed pairs again without the approval screen ([c408cd2](https://github.com/masksrb/masks/commit/c408cd2e10d7cdb3846b3aac37aecc67d3cc1421))
* **server:** a second factor screen that can offer nothing says the sign-in cannot continue, and names what settles it ([6d31d65](https://github.com/masksrb/masks/commit/6d31d65787df2e4a3c50000f3f817433c5d8b417))
* **server:** a sign-in can be approved from a device you trusted, by entering the code it shows ([1c133e6](https://github.com/masksrb/masks/commit/1c133e6183167e6bc077e2b522d674b0b2815bee))
* **server:** a sign-in can be confirmed with a code sent by email or text message ([1097356](https://github.com/masksrb/masks/commit/1097356464a903478c74017591e92ac79a679a17))
* **server:** a sign-in policy can ask for a second factor again at every app sign-in that has not used one ([4b2cbb8](https://github.com/masksrb/masks/commit/4b2cbb8df8ff96bbe7006a1989fed08388907190))
* **server:** a sign-in policy can offer a code emailed to the person as a first factor, with or without a password ([86993e6](https://github.com/masksrb/masks/commit/86993e6416b9e12669686012f930bf1826758853))
* **server:** a sign-in policy sets how long a session lasts and how long it may sit idle, and a stricter app asks again ([1e33d72](https://github.com/masksrb/masks/commit/1e33d72f68305eb8c0bea970c3a1ec03bac2e244))
* **server:** a signed-out visit to the account page goes straight to sign-in, which asks you to sign in to continue ([1158748](https://github.com/masksrb/masks/commit/115874896a5de797116928db5432024ae80ed1ff))
* **server:** a tenant keeps its activity for up to seven years, and any manager downloads a range of it ([777c670](https://github.com/masksrb/masks/commit/777c67095f8a6b616ff119f7e5f08edf94e81094))
* **server:** a tenant proves a domain with a DNS record, and an address there goes straight to its provider ([c22fdf1](https://github.com/masksrb/masks/commit/c22fdf1e62a16354c83f4b46c8ed7d971d8e8b86))
* **server:** a tenant serves sign-in from its own host within a domain it has proven ([345a09d](https://github.com/masksrb/masks/commit/345a09d3a107a805c8a0555fbf28532ff70f6648))
* **server:** an organization brings its own sign-in policy, provider, and directory ([f8ae7bc](https://github.com/masksrb/masks/commit/f8ae7bc41ab12c847ac46d13cdd705e1097c9ef3))
* **server:** an organization invitation expires after two weeks, and an owner or manager sends it again ([5301d64](https://github.com/masksrb/masks/commit/5301d64e927258c03e55f0b6e8d49410a553ab11))
* **server:** an organization's owners add, promote, and remove its members from their own account page ([1693f42](https://github.com/masksrb/masks/commit/1693f423e1925ecda33be6507f41357520ab56ab))
* **server:** an owner manages members from the account page in one row each, and hears back inside the organization they changed ([b8b80ad](https://github.com/masksrb/masks/commit/b8b80ad15494c269af55a2fe37c2c23099785c0d))
* **server:** being added to an organization is an invitation the person accepts, and it grants nothing until they do ([88f783e](https://github.com/masksrb/masks/commit/88f783e9aefdaa12626afe050ade777d7699080d))
* **server:** each sign-in is scored for risk, and a policy asks for a second factor or refuses from a score it names ([d4986c2](https://github.com/masksrb/masks/commit/d4986c2c1303659b95061048845043edb6280980))
* **server:** events record the organization they belong to, and a stream can send one organization's events to that customer ([f797a2d](https://github.com/masksrb/masks/commit/f797a2d1498b8ca9f9c6c3b3f1a6a5ec52b69bf9))
* **server:** every email knows its journey, and one sent while signing in to an approved app is headed by that app ([e6a0e64](https://github.com/masksrb/masks/commit/e6a0e64de960fa778ef50c7f89c4a9f00958a439))
* **server:** every event a tenant records can be streamed to a signed HTTPS endpoint, managed through the manage API ([03b525c](https://github.com/masksrb/masks/commit/03b525c5e682928274d16181469790e4e6b92a4f))
* **server:** every token exchange is recorded, granted or refused, and never with the token it was handed ([00dc04b](https://github.com/masksrb/masks/commit/00dc04b09ed3b66ca2ce173e4da3066e8fbe6a46))
* **server:** idle accounts are suspended and then deleted on two stacked timers ([2f6c201](https://github.com/masksrb/masks/commit/2f6c201ad90155df572fc8a329b9f716c5c84b62))
* **server:** idle accounts are warned, then suspended or deleted, and a person can delete their own account ([65c0c78](https://github.com/masksrb/masks/commit/65c0c78ac7067166da9330f05defb70e1a54feb5))
* **server:** manage lays its sections straight onto the page, with no card around them ([22c6e84](https://github.com/masksrb/masks/commit/22c6e8482e2b412095a7d4e87c21839ef062e41e))
* **server:** manage lists actors, clients and activity twenty-five to a page, with how many there are ([aef9555](https://github.com/masksrb/masks/commit/aef9555d7071f4370fd931a6492c1cb7bc520d35))
* **server:** manage previews every email masks sends, rendered from its templates ([e653c04](https://github.com/masksrb/masks/commit/e653c04249ba1a3b4d4620dc0ff3a2a1252ec7a8))
* **server:** manage's header opens settings from a cog, and settings shows who you are with a link to your account ([31a8a3c](https://github.com/masksrb/masks/commit/31a8a3c1c1266b0cfe0ddb2096a72f2095fe22fe))
* **server:** managers can hold read, support, or security roles instead of every permission, and each mutation names the least it needs ([9757385](https://github.com/masksrb/masks/commit/9757385c1ca2860a0680f98f4bc80ac646dbd1ae))
* **server:** masks is a Shared Signals transmitter, pushing signed CAEP and RISC events to the receivers people use ([0c4cd6d](https://github.com/masksrb/masks/commit/0c4cd6d8474ad7bf185b58782cf3f6a4c89be587))
* **server:** masks mounts inside another Rails app, in engine mode ([103751f](https://github.com/masksrb/masks/commit/103751fe4f78f084ffe1643fab3eb9ec464d56c4))
* **server:** organizations hold members in roles, and an app that asks for the organization scope signs a person in as one of them ([5b504e3](https://github.com/masksrb/masks/commit/5b504e34b9af49de73a7a192cfad4cb8718954f7))
* **server:** the connect screen asks one fixed question and says the rest in a line ([230afad](https://github.com/masksrb/masks/commit/230afad6a84bbc920d47b74e86e455cec93fc427))
* **server:** the consent screen shows who is signing in under its heading, as the connect screen does ([22391b0](https://github.com/masksrb/masks/commit/22391b01256aaf3404d1469c6e5d9d6cf23a1d76))
* **server:** the manage console shows an organization at a glance, with its members, roles, sign-in, domains, and what archiving it revokes ([a81cfb5](https://github.com/masksrb/masks/commit/a81cfb550a6c9031c8ae8e374b1c31cddb6c74cd))
* **server:** the manage console's overview counts organizations and lists them, flagging any left without an owner ([242aa3e](https://github.com/masksrb/masks/commit/242aa3ef43f0a349e4c0040996c63eed0d5445b9))
* **server:** userinfo and introspection name the organization a token was issued for, with the role held in it now ([4736f4f](https://github.com/masksrb/masks/commit/4736f4fd187e459bd2a3bcde145bcd60912c79b8))
* **server:** userinfo lists every organization a person has joined, with the role held in each, to an app granted the organization scope ([d64aca4](https://github.com/masksrb/masks/commit/d64aca40e7a4fb9452c5e1fc937adb8ab995ddd1))


### Fixes

* **server:** a delegation needs consent given to its own request, and an emailed link is bound to the address it was sent to ([9a02369](https://github.com/masksrb/masks/commit/9a02369e63a0bd3c5fe4b4c4238181fed87a9a4b))
* **server:** a device sign-in carries the organization it was approved for, and loses it when the membership ends ([66b391c](https://github.com/masksrb/masks/commit/66b391c6b9a41d60f600d39c5f19cc725b25eb25))
* **server:** a provider may point at a name under .localhost over plain http, as an application's redirect already may ([c2690f6](https://github.com/masksrb/masks/commit/c2690f6677710e5eb87b7ac5e249cd7d3126444b))
* **server:** a resource whose metadata could not be read is asked again at the next sign-in ([1de66ee](https://github.com/masksrb/masks/commit/1de66eec4ac0037c965b708aadca4dffd5fded9a))
* **server:** a role change ends tokens minted under the old role and is signalled, owners invite only whom sign-up would admit, and an invitation is accepted only from its confirmed address ([de7cf6f](https://github.com/masksrb/masks/commit/de7cf6ff92705483c1a7c804306d468e43baa977))
* **server:** allowing an app back in after cutting it off from the account page no longer fails ([d22a2c4](https://github.com/masksrb/masks/commit/d22a2c45c5afcb19a720edfa70e1482592be7d0a))
* **server:** an actor's page shows the externalId each organization's directory holds for them, and the tally no longer counts live sessions nobody reads ([fc34561](https://github.com/masksrb/masks/commit/fc34561c4afba778aebcc1fd808b600731c45f56))
* **server:** an app that names an organization on /authorize reaches it, instead of the token's empty organization ([4dc0308](https://github.com/masksrb/masks/commit/4dc0308269b65d1f328684f93f9e8647edb20e7a))
* **server:** an emailed code reveals no account, waits for a hidden policy's proof, and cannot confirm someone else's sign-up ([f133e6a](https://github.com/masksrb/masks/commit/f133e6ad969ab81c5adb0097148c62014791f449))
* **server:** an empty invitation is refused, a URL-named groups claim is read whole, and an invited row shows only what was typed ([fbb9456](https://github.com/masksrb/masks/commit/fbb9456c28a4c206d650d108fd2ef086f4dbed07))
* **server:** an organization named on /authorize governs the sign-in only after the person proves they belong to it ([d4eff78](https://github.com/masksrb/masks/commit/d4eff780807247c9e23d6c4a20bda767deb2792c))
* **server:** an organization's directory changes only accounts it created, and only an owner issues provisioning that reaches managers ([7c0ff3c](https://github.com/masksrb/masks/commit/7c0ff3c40517c821a3fdd1833f5d5e9607426c3e))
* **server:** an organization's directory keeps its own externalId for each member, and every taken userName, email, or externalId is refused with the same conflict ([feecbd4](https://github.com/masksrb/masks/commit/feecbd47de8213c65ea4f28a58f080f745482631))
* **server:** an organization's provisioning token sets only addresses at domains proven for it, so it can neither probe nor squat anyone else's ([85ec048](https://github.com/masksrb/masks/commit/85ec0483a21b585feb5d31270ae92ea84fabcce1))
* **server:** an organization's provisioning token verifies only addresses at its own domains, and a pending invitation elsewhere no longer blocks its deprovisioning ([b5ed028](https://github.com/masksrb/masks/commit/b5ed0284bcbf9912115aa1898b61e0e87eb20ef1))
* **server:** an organization's sign-in policy holds a person to its own first factors, providers, and domains, not only its second factor ([14dbf6a](https://github.com/masksrb/masks/commit/14dbf6af0ad16dc226e011319bba663d0a5d303c))
* **server:** discovery names the orgs claim among the claims it supports ([5a85621](https://github.com/masksrb/masks/commit/5a856218d72e0d74bb5cb851358a0cf44fb44c0f))
* **server:** email and text message codes are asked for under every policy, and an emailed password reset turns email codes off ([805dfae](https://github.com/masksrb/masks/commit/805dfaed23101e8b4106698c22f04f425ddb6efb))
* **server:** every account holding openid gains identities in every tenant, which the migration that first granted it could not reach through row-level security ([62d6326](https://github.com/masksrb/masks/commit/62d632691479cb1b1a8f87febd98c1bec26185b4))
* **server:** group-mapped roles reach organizations, a refused risky sign-in stays refused, and invited members show only their address ([761de95](https://github.com/masksrb/masks/commit/761de95c238b1ca591d3f9eadaa8dbe2f96360fc))
* **server:** invitations that were open before expiry arrived are backfilled in every tenant, and one without a send time counts from when it was made ([c33ad8e](https://github.com/masksrb/masks/commit/c33ad8ee38c4dfa5b2b28fe9c0b23df76cdf9516))
* **server:** the idle sweep rechecks each account under a lock, and a failed refresh no longer counts as use ([932c277](https://github.com/masksrb/masks/commit/932c277b30af3fa48428a95a5b7526daa56462dd))
* **server:** the origin masks puts in links and tokens comes from the tenant, never from the request's host ([700ac4c](https://github.com/masksrb/masks/commit/700ac4cfae850fc82af6a127b6411cbba15b6827))
* **server:** the person who creates an organization is its owner, instead of having to invite and accept themselves ([846fc1d](https://github.com/masksrb/masks/commit/846fc1d153d3983e1640533ffebd55daa920c6ee))
* **server:** the provider's own jobs carry their tenant, and nothing else's do ([59a1b59](https://github.com/masksrb/masks/commit/59a1b595bc0a133967bd891374fa127dd34e1d24))


### Performance

* **server:** SCIM reads each user in one query through a directory that knows where its externalId lives, and an externalId filter matches exactly so its index serves it ([c43dffa](https://github.com/masksrb/masks/commit/c43dffa55b453e09d5480a14291950e88401c1b3))


### Refactoring

* **server:** a SCIM filter compares through Arel nodes instead of SQL built from strings ([82888d8](https://github.com/masksrb/masks/commit/82888d8db41db04d61cfc1ca4fc6f263038afb9c))
* **server:** a suspension records its reason, and the idle sweep tells the mailer which warning to send ([84fd54b](https://github.com/masksrb/masks/commit/84fd54bd11557e3dabe2790d0b4f9eba3c670949))
* **server:** an invitation's expiry, an organization's claim, and the account page's scoped notes each live in one place, and the console counts members for every listed organization at once ([06f6828](https://github.com/masksrb/masks/commit/06f6828a0a509d2c36f879eb55e99f3dfac26dd2))
* **server:** an unaccepted membership is never an owner, owner-only scopes live in one list, and memberships gain their columns in one migration ([9659d05](https://github.com/masksrb/masks/commit/9659d05d0d39a2090f71fb98ac395c4a3f4f61e1))
* **server:** emailed codes share the resend form, crowding check, and email confirmation with the flows before them ([901bfa9](https://github.com/masksrb/masks/commit/901bfa98ad7bdbb0052a17b8fed36651c71a4415))
* **server:** every way a person joins an organization makes the membership and records it in one step ([f41b610](https://github.com/masksrb/masks/commit/f41b610750ab2a3b3d135eb6f338871c7ab258ce))
* **server:** SCIM groups load their members in a few queries, share paging with users, and an organization refuses to drop a role someone holds ([b0080ca](https://github.com/masksrb/masks/commit/b0080cad3f905db2a53ea2926d97ea7bc8742a5a))
* **server:** second factors finish through one helper, and code factors read one table per channel ([e617dc4](https://github.com/masksrb/masks/commit/e617dc4a2b9f8dabc2f9a04ac52a5db9745a9c57))
* **server:** the organization claim is built in one place, an invitation's wording lives once, and no one is told about a membership change they made themselves ([85d4c49](https://github.com/masksrb/masks/commit/85d4c49b24a97ee3d7bae0ec68f4ce2e0c6bdadf))
* **server:** the provider is the masks-server engine, and server/ mounts it ([baabad1](https://github.com/masksrb/masks/commit/baabad19b0bca65b5077c7e6644918aafdca871f))
* **server:** the setup token's length is checked with the rest of masks' configuration ([01c4bff](https://github.com/masksrb/masks/commit/01c4bfff084a099818e951defd5cf4b414d2d24f))
