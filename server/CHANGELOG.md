# Changelog

## [0.4.0](https://github.com/masksrb/masks/compare/server-v0.3.0...server-v0.4.0) (2026-10-04)


### Features

* **engine:** a client_id that is the https URL of a client metadata document signs people in without registering first, as MCP clients do ([86dd5b6](https://github.com/masksrb/masks/commit/86dd5b61adf51f2dc0c294777eb2ed4af6fec5f7))
* **engine:** a consent remembers the authorization details a declared type allows, and a client's consents can expire ([bdfc149](https://github.com/masksrb/masks/commit/bdfc1496fe9f0a8df2aec8becb4b9637f23b200c))
* **engine:** an owner rewords the subject and opening of the invitation, reset, confirmation, code, and approval emails, and adds a signature to every email ([eb74a02](https://github.com/masksrb/masks/commit/eb74a023994628f1a19cce6e12d822e17ef1181e))
* **engine:** masks receives shared signals at /ssf/events, and a provider that revokes a session or disables an account signs that person out here ([7e627fe](https://github.com/masksrb/masks/commit/7e627fe62734c1356f56c1913f7ff45988044848))
* **engine:** rich authorization requests (RFC 9396) carry authorization_details from /authorize to the token, checked against types an approved client declares ([18dc29a](https://github.com/masksrb/masks/commit/18dc29a985b67b95e2e682b87a8a29829607a735))
* **server:** /up answers down with a 503 while the database, the job queue, or the cache cannot be reached ([6016276](https://github.com/masksrb/masks/commit/6016276a735a00ca34c5079b0ba5ae40dba8c83f))
* **server:** a saved passkey is offered in the identifier field's autofill, through a conditional WebAuthn request ([398e6e0](https://github.com/masksrb/masks/commit/398e6e0066b44f45b437fd3de67452384175cc08))


### Fixes

* devalue 5.9.4 and brace-expansion 5.0.12 close the open Dependabot advisories that have a fix ([891e302](https://github.com/masksrb/masks/commit/891e302351d278e2f7ed462566624bd2690e37c6))
* **server:** the image builds from a cold cache again, with the test assets built in the test stage that has the test gems ([f41ce6d](https://github.com/masksrb/masks/commit/f41ce6dfcb1fc77b873a3b3d38c4afb2efdcae99))


### Documentation

* every guide, the reference prose, and the READMEs are checked against the code, shortened, and corrected ([94782d1](https://github.com/masksrb/masks/commit/94782d1fbfe363e90c40f0c728a241de9738e138))
* the plan holds only what is left, and the READMEs match the engine layout and the code ([1615722](https://github.com/masksrb/masks/commit/1615722f88ae5f7d19955ff686dcef9f64a6326f))


### Refactoring

* **engine:** methods nothing calls, the scaffold PWA views and Current.session go ([9d126ec](https://github.com/masksrb/masks/commit/9d126ec1c550950e8b4eec0ce58a0f0b474d4ffa))
* **engine:** one partial carries a tenant's email wording, one query loads it, and authorization_details narrow in one place ([1b2df29](https://github.com/masksrb/masks/commit/1b2df29380b2c2c8dc6b87d45d60b4ef23255b26))
* **server:** stylesheet rules no page uses, and dev settings from the auth.test layout, go ([01e3d3f](https://github.com/masksrb/masks/commit/01e3d3fc095f33422194c4d6fd8f94fef6f22429))
* **server:** Thruster, capybara and the stale schema dumps go ([292b179](https://github.com/masksrb/masks/commit/292b1791e43ad4624fa743603206b8d178ebae36))

## [0.3.0](https://github.com/masksrb/masks/compare/server-v0.2.0...server-v0.3.0) (2026-09-28)


### ⚠ BREAKING CHANGES

* **server:** the icons are served at /masks-public/icon.svg, /masks-public/icon.png, and /masks-public/favicon.svg. SMTP settings apply to masks' own mailer, not ActionMailer::Base.
* **server:** job classes in recurring.yml and anything naming a provider class are now Masks::Server::*.
* **server:** the original migrations are edited in place. Existing databases must be rebuilt.
* **server:** the image listens on 3000, not 80, and SOLID_QUEUE_IN_PUMA is now MASKS_JOBS_IN_WEB_SERVER, on by default. A deployment that runs its own bin/jobs container sets it to false.
* a resource server on an older gem still accepts the new tokens, but this gem refuses access tokens from a server that does not type them.

### Features

* an access token is typed at+jwt, and nothing takes a token of another type in its place ([d0b4cfd](https://github.com/masksrb/masks/commit/d0b4cfdf802053359695495d417225e3a1578302))
* **server:** a canonical person card shows who is signed in ([cc4d294](https://github.com/masksrb/masks/commit/cc4d294dba5c0e55c5b31cbf76ec1c079664ba8a))
* **server:** a canonical person card shows who is signed in ([5df0aac](https://github.com/masksrb/masks/commit/5df0aacfbf795230d6004cd835f10c45b2d4c378))
* **server:** a client authenticates with an assertion signed by its own key ([532a497](https://github.com/masksrb/masks/commit/532a497b0ea16c1b2427e28368d18d61912d8a1e))
* **server:** a client's logo, home page, terms and privacy policy are shown when people are asked to let it in ([4ac3885](https://github.com/masksrb/masks/commit/4ac3885e30111beb62e989dadd701ea78c77a476))
* **server:** a client's page edits everything the manage API can, and says how its sign-in policy differs from the default ([4fa26fc](https://github.com/masksrb/masks/commit/4fa26fccd4cdc7b65684456e5c0e09305342cb0c))
* **server:** a freshly created tenant prints a setup token in its logs, and the first account is not created without it ([e91af7c](https://github.com/masksrb/masks/commit/e91af7c8f72e7c1471bf8131e84116ff11aa2558))
* **server:** a passkey on the second factor screen trusts the device when asked to, and an account holding a passkey alone is offered the trust box ([e079aa2](https://github.com/masksrb/masks/commit/e079aa28a8fff0f9152ed610b45177576e46fd05))
* **server:** a second factor screen that can offer nothing says the sign-in cannot continue, and names what settles it ([6d31d65](https://github.com/masksrb/masks/commit/6d31d65787df2e4a3c50000f3f817433c5d8b417))
* **server:** a service with nobody behind it signs in as itself with client_credentials ([61e1f43](https://github.com/masksrb/masks/commit/61e1f434bc8fcfdb4a8e29da6999190fc3d4432b))
* **server:** a sign-in can be approved from a device you trusted, by entering the code it shows ([1c133e6](https://github.com/masksrb/masks/commit/1c133e6183167e6bc077e2b522d674b0b2815bee))
* **server:** a sign-in can be confirmed with a code sent by email or text message ([1097356](https://github.com/masksrb/masks/commit/1097356464a903478c74017591e92ac79a679a17))
* **server:** a sign-in policy can ask for a second factor again at every app sign-in that has not used one ([4b2cbb8](https://github.com/masksrb/masks/commit/4b2cbb8df8ff96bbe7006a1989fed08388907190))
* **server:** a sign-in policy can offer a code emailed to the person as a first factor, with or without a password ([86993e6](https://github.com/masksrb/masks/commit/86993e6416b9e12669686012f930bf1826758853))
* **server:** a sign-in policy sets how long a session lasts and how long it may sit idle, and a stricter app asks again ([1e33d72](https://github.com/masksrb/masks/commit/1e33d72f68305eb8c0bea970c3a1ec03bac2e244))
* **server:** a sign-in policy that hides who has an account sends any email address a code before anything else ([73e3d89](https://github.com/masksrb/masks/commit/73e3d8904ba3281c4375fc12001be5a698bdc758))
* **server:** a sign-in policy that offers only passkeys signs people up with a passkey and no password ([73e3d89](https://github.com/masksrb/masks/commit/73e3d8904ba3281c4375fc12001be5a698bdc758))
* **server:** a tenant keeps its activity for up to seven years, and any manager downloads a range of it ([777c670](https://github.com/masksrb/masks/commit/777c67095f8a6b616ff119f7e5f08edf94e81094))
* **server:** a tenant or a client restyles the sign-in and account pages with a theme file ([cee38d1](https://github.com/masksrb/masks/commit/cee38d1538f92e899a8ae24af2555a43d34eaf5a))
* **server:** a tenant proves a domain with a DNS record, and an address there goes straight to its provider ([c22fdf1](https://github.com/masksrb/masks/commit/c22fdf1e62a16354c83f4b46c8ed7d971d8e8b86))
* **server:** a tenant serves sign-in from its own host within a domain it has proven ([345a09d](https://github.com/masksrb/masks/commit/345a09d3a107a805c8a0555fbf28532ff70f6648))
* **server:** a token exchange takes an ID token or an actor token, and says who is acting ([9d771be](https://github.com/masksrb/masks/commit/9d771be0b49cf453fba41923e6910053d9e686cd))
* **server:** an authorization request can be signed by the client that makes it ([49c30e3](https://github.com/masksrb/masks/commit/49c30e36aa465b74a555b8b07b5e613d7167eb2d))
* **server:** an identity provider adds, changes, suspends and removes people over SCIM 2.0 ([09c2025](https://github.com/masksrb/masks/commit/09c2025059b3642d6196956b929cb21357e5c780))
* **server:** an organization brings its own sign-in policy, provider, and directory ([f8ae7bc](https://github.com/masksrb/masks/commit/f8ae7bc41ab12c847ac46d13cdd705e1097c9ef3))
* **server:** an organization invitation expires after two weeks, and an owner or manager sends it again ([5301d64](https://github.com/masksrb/masks/commit/5301d64e927258c03e55f0b6e8d49410a553ab11))
* **server:** an organization's owners add, promote, and remove its members from their own account page ([1693f42](https://github.com/masksrb/masks/commit/1693f423e1925ecda33be6507f41357520ab56ab))
* **server:** an owner manages members from the account page in one row each, and hears back inside the organization they changed ([b8b80ad](https://github.com/masksrb/masks/commit/b8b80ad15494c269af55a2fe37c2c23099785c0d))
* **server:** being added to an organization is an invitation the person accepts, and it grants nothing until they do ([88f783e](https://github.com/masksrb/masks/commit/88f783e9aefdaa12626afe050ade777d7699080d))
* **server:** each sign-in is scored for risk, and a policy asks for a second factor or refuses from a score it names ([d4986c2](https://github.com/masksrb/masks/commit/d4986c2c1303659b95061048845043edb6280980))
* **server:** events record the organization they belong to, and a stream can send one organization's events to that customer ([f797a2d](https://github.com/masksrb/masks/commit/f797a2d1498b8ca9f9c6c3b3f1a6a5ec52b69bf9))
* **server:** every email knows its journey, and one sent while signing in to an approved app is headed by that app ([e6a0e64](https://github.com/masksrb/masks/commit/e6a0e64de960fa778ef50c7f89c4a9f00958a439))
* **server:** every event a tenant records can be streamed to a signed HTTPS endpoint, managed through the manage API ([03b525c](https://github.com/masksrb/masks/commit/03b525c5e682928274d16181469790e4e6b92a4f))
* **server:** idle accounts are suspended and then deleted on two stacked timers ([2f6c201](https://github.com/masksrb/masks/commit/2f6c201ad90155df572fc8a329b9f716c5c84b62))
* **server:** idle accounts are warned, then suspended or deleted, and a person can delete their own account ([65c0c78](https://github.com/masksrb/masks/commit/65c0c78ac7067166da9330f05defb70e1a54feb5))
* **server:** manage adds a Streams tab to add, test, rotate, and archive event streams ([bbe2ea1](https://github.com/masksrb/masks/commit/bbe2ea193505f0b2864c0d6a1c95231a8dc88210))
* **server:** manage calls them actors, at /manage/actors ([d9567cc](https://github.com/masksrb/masks/commit/d9567cc407b475983b89ac31d8d248de31e4b26e))
* **server:** manage lays its sections straight onto the page, with no card around them ([22c6e84](https://github.com/masksrb/masks/commit/22c6e8482e2b412095a7d4e87c21839ef062e41e))
* **server:** manage lists actors, clients and activity twenty-five to a page, with how many there are ([aef9555](https://github.com/masksrb/masks/commit/aef9555d7071f4370fd931a6492c1cb7bc520d35))
* **server:** manage offers email and text message codes on a policy, and turns them off for an actor ([6efe9c4](https://github.com/masksrb/masks/commit/6efe9c49732482fa986ec20cdb22b4a57dc37621))
* **server:** manage previews every email masks sends, rendered from its templates ([e653c04](https://github.com/masksrb/masks/commit/e653c04249ba1a3b4d4620dc0ff3a2a1252ec7a8))
* **server:** manage reads a step larger again, controls included ([dc7bbed](https://github.com/masksrb/masks/commit/dc7bbed949282fb82598bd35175736523248bfe7))
* **server:** manage reads larger, keeps help in a tooltip beside each title, and lays settings out beside their labels ([ed71cd9](https://github.com/masksrb/masks/commit/ed71cd9c19f4dd1dc0436854a3e3834cd0333988))
* **server:** manage's header opens settings from a cog, and settings shows who you are with a link to your account ([31a8a3c](https://github.com/masksrb/masks/commit/31a8a3c1c1266b0cfe0ddb2096a72f2095fe22fe))
* **server:** managers can hold read, support, or security roles instead of every permission, and each mutation names the least it needs ([9757385](https://github.com/masksrb/masks/commit/9757385c1ca2860a0680f98f4bc80ac646dbd1ae))
* **server:** masks is a Shared Signals transmitter, pushing signed CAEP and RISC events to the receivers people use ([0c4cd6d](https://github.com/masksrb/masks/commit/0c4cd6d8474ad7bf185b58782cf3f6a4c89be587))
* **server:** masks mounts inside another Rails app, in engine mode ([103751f](https://github.com/masksrb/masks/commit/103751fe4f78f084ffe1643fab3eb9ec464d56c4))
* **server:** masks signs people into SAML applications as their identity provider ([c929fdc](https://github.com/masksrb/masks/commit/c929fdcb8cd7453c87bb9aa549e63e92e056c0f5))
* **server:** masks-server is released to RubyGems alongside the image ([653b3c0](https://github.com/masksrb/masks/commit/653b3c0e5deb83f18bafad468d78b954e399269a))
* **server:** organizations hold members in roles, and an app that asks for the organization scope signs a person in as one of them ([5b504e3](https://github.com/masksrb/masks/commit/5b504e34b9af49de73a7a192cfad4cb8718954f7))
* **server:** people and devices are one page in manage ([35548b5](https://github.com/masksrb/masks/commit/35548b531e75536ea09379e9e98c063a07ed42ca))
* **server:** settings in manage are one column, with the sections in a row across the top ([66e3ba4](https://github.com/masksrb/masks/commit/66e3ba407a9a769b2e9c3b48dc27a1a59e8ec979))
* **server:** the connect screen asks one fixed question and says the rest in a line ([230afad](https://github.com/masksrb/masks/commit/230afad6a84bbc920d47b74e86e455cec93fc427))
* **server:** the connect screen says what it registers and what it allows, and waits five seconds before either can happen ([d420eb3](https://github.com/masksrb/masks/commit/d420eb336bc4639fa455d91bc5cb74d73ac45b90))
* **server:** the consent screen shows who is signing in under its heading, as the connect screen does ([22391b0](https://github.com/masksrb/masks/commit/22391b01256aaf3404d1469c6e5d9d6cf23a1d76))
* **server:** the container derives its secrets from one master key ([68b9897](https://github.com/masksrb/masks/commit/68b9897f19a5e7838f475648a64c92efdcae2d83))
* **server:** the container generates and persists its own secrets on first boot ([61158c4](https://github.com/masksrb/masks/commit/61158c42f457deb7ffc78bebf709f72c2e1cf4fa))
* **server:** the general and provisioning settings stack their cards in one column ([85bacad](https://github.com/masksrb/masks/commit/85bacad887996dc37bfae7cdd7b77bd26ff6dd2e))
* **server:** the image runs Puma alone on port 3000, with jobs in the same process ([203990f](https://github.com/masksrb/masks/commit/203990f84ad858689657766911dc55f3832d8c70))
* **server:** the manage console is finished in lacquer, with raised panels lit from above, pressed-in wells, keys that press, and a floating tab tray on neutral black and gray ([4a501f5](https://github.com/masksrb/masks/commit/4a501f59d4ec4f01ff0dc9b8f1b57fa460e95a8d))
* **server:** the manage console lays out for the desktop in a crisp system face, with flat panels, one stats strip, a dashboard grid, and quiet sentence-case labels ([42ee3a3](https://github.com/masksrb/masks/commit/42ee3a3f85f0dfe4ffb0a064c1fb30a794bab8b3))
* **server:** the manage console shows an organization at a glance, with its members, roles, sign-in, domains, and what archiving it revokes ([a81cfb5](https://github.com/masksrb/masks/commit/a81cfb550a6c9031c8ae8e374b1c31cddb6c74cd))
* **server:** the manage console's overview counts organizations and lists them, flagging any left without an owner ([242aa3e](https://github.com/masksrb/masks/commit/242aa3ef43f0a349e4c0040996c63eed0d5445b9))
* **server:** the overview counts actors, clients, organizations, and devices, each labeled above its figure and pointing to its page on hover ([5b89444](https://github.com/masksrb/masks/commit/5b89444e8ca7d19bdbae2a862242a78612c6e533))
* **server:** the person card is a frosted pane like the panels around it ([2f79a67](https://github.com/masksrb/masks/commit/2f79a67d3fa40b8d01835f98f905f8ce1ef123e6))
* **server:** the sign-in and account pages are lit by the rose window, with frosted panes, brass came, and an ember action ([dda4044](https://github.com/masksrb/masks/commit/dda40440a247d3c7b6c68385bf8406497fd5f9e3))
* **server:** tokens and adapters store a kind, not a class name ([138628a](https://github.com/masksrb/masks/commit/138628a8d82a22a09fe60e6f08d4340c9c4fb718))


### Fixes

* **server:** a browser signed in to one account no longer passes for another's second factor ([37b6b26](https://github.com/masksrb/masks/commit/37b6b26bbd8407fd9f7ce9ac7bab0c9204e06181))
* **server:** a browser without javascript signs in with its password instead of asking to reset it ([2904954](https://github.com/masksrb/masks/commit/29049541224636547db157056562c08f1279e0f8))
* **server:** a client's home page, logo, terms and privacy policy must be http URLs ([4ac3885](https://github.com/masksrb/masks/commit/4ac3885e30111beb62e989dadd701ea78c77a476))
* **server:** a client's links are checked again where they are shown, and fetching its logo gives up on a slow host ([00ea777](https://github.com/masksrb/masks/commit/00ea7771d2e22d20c04a9817d467d6d61a605c57))
* **server:** a manage console paired before the role scopes pairs again instead of stopping on invalid_scope ([5bcde4e](https://github.com/masksrb/masks/commit/5bcde4eab16e928188691c24da9b570b88da3064))
* **server:** a refused passkey does not claim the device holds none, and a pasted code is accepted ([9959322](https://github.com/masksrb/masks/commit/99593223012b870c25b998f1f984c2c2dbd02059))
* **server:** a SAML request cannot be forged past its signature, and an unconfirmed email is never asserted ([b89761b](https://github.com/masksrb/masks/commit/b89761b8dc6f9c839c9cfd00f58e42595429d18f))
* **server:** a wide row on a phone no longer widens the manage console and pushes its tab bar out of reach ([b9bac79](https://github.com/masksrb/masks/commit/b9bac7931a20f0a8ac0ca9c07e468cd007e7f750))
* **server:** an actor's page shows the externalId each organization's directory holds for them, and the tally no longer counts live sessions nobody reads ([fc34561](https://github.com/masksrb/masks/commit/fc34561c4afba778aebcc1fd808b600731c45f56))
* **server:** an emailed code reveals no account, waits for a hidden policy's proof, and cannot confirm someone else's sign-up ([f133e6a](https://github.com/masksrb/masks/commit/f133e6ad969ab81c5adb0097148c62014791f449))
* **server:** an empty invitation is refused, a URL-named groups claim is read whole, and an invited row shows only what was typed ([fbb9456](https://github.com/masksrb/masks/commit/fbb9456c28a4c206d650d108fd2ef086f4dbed07))
* **server:** an organization's directory changes only accounts it created, and only an owner issues provisioning that reaches managers ([7c0ff3c](https://github.com/masksrb/masks/commit/7c0ff3c40517c821a3fdd1833f5d5e9607426c3e))
* **server:** an organization's directory keeps its own externalId for each member, and every taken userName, email, or externalId is refused with the same conflict ([feecbd4](https://github.com/masksrb/masks/commit/feecbd47de8213c65ea4f28a58f080f745482631))
* **server:** an organization's sign-in policy holds a person to its own first factors, providers, and domains, not only its second factor ([14dbf6a](https://github.com/masksrb/masks/commit/14dbf6af0ad16dc226e011319bba663d0a5d303c))
* **server:** every account holding openid gains identities in every tenant, which the migration that first granted it could not reach through row-level security ([62d6326](https://github.com/masksrb/masks/commit/62d632691479cb1b1a8f87febd98c1bec26185b4))
* **server:** every page masks serves carries a content security policy ([e33c164](https://github.com/masksrb/masks/commit/e33c164e668ecd00469743e14f1ea81ba78a5092))
* **server:** masks refuses to boot in production without its own encryption keys ([2169181](https://github.com/masksrb/masks/commit/21691813c4934caa6ed896372415e2b1edebfdd9))
* **server:** production connects to Postgres on 5432 unless POSTGRES_PORT says otherwise ([0e9aad7](https://github.com/masksrb/masks/commit/0e9aad7b75b35801b38475afb7e661807a73ec10))
* **server:** production refuses a MASKS_SETUP_TOKEN shorter than 24 characters ([b57a2c5](https://github.com/masksrb/masks/commit/b57a2c5bc04a43e737312c5fb0a8891867bb2876))
* **server:** proving an inbox in hidden mode confirms no account until that account signs in, and counts for nobody else ([00ea777](https://github.com/masksrb/masks/commit/00ea7771d2e22d20c04a9817d467d6d61a605c57))
* **server:** signing out of masks takes one click, and the confirmation says what it does ([a869755](https://github.com/masksrb/masks/commit/a869755ae87a428a5fc461e8b78ae5081da47939))
* **server:** signing out of masks takes one click, and the confirmation says what it does ([097d0fd](https://github.com/masksrb/masks/commit/097d0fdc7d461874460c647cd580b4867b130bf2))
* **server:** the dark console raises its cards above the page and gives secondary text readable contrast ([d14527a](https://github.com/masksrb/masks/commit/d14527a93d52f047b733b3c28184ff54a2e57b33))
* **server:** the dev entrypoint names the authenticator job by its namespace ([1ed425b](https://github.com/masksrb/masks/commit/1ed425bde95961e062fec1c63852d4920853603a))
* **server:** the favicon sits on the mark's black ([3ec6f86](https://github.com/masksrb/masks/commit/3ec6f86ae532700d5397fbb45818b179587d3ba3))
* **server:** the idle sweep rechecks each account under a lock, and a failed refresh no longer counts as use ([932c277](https://github.com/masksrb/masks/commit/932c277b30af3fa48428a95a5b7526daa56462dd))
* **server:** the manage console keeps a steady gutter on phones, fits its chart labels and tooltips on screen, leads an odd tally with its first count, and keeps member and client rows inside the page ([a2e7ba1](https://github.com/masksrb/masks/commit/a2e7ba105aaad4fcfcbc25956bea55bbd3bd284f))
* **server:** the second factor screen names what it asks for, and says when the device holds no passkey ([b4fcce4](https://github.com/masksrb/masks/commit/b4fcce4af6775d26c75988b075ff3798a2009435))


### Documentation

* Rails apps covers client, server, and engine mode ([41454a2](https://github.com/masksrb/masks/commit/41454a242438e4df246dcbc4dce94b6d8a022239))
* the homepage links each column to a guide, and self-hosting covers secrets, tags, and Caddy ([c3d2409](https://github.com/masksrb/masks/commit/c3d24096bec35492e5eeb31d922c4aa992a87188))


### Refactoring

* **server:** a client's logo is stamped on the client, and avatars and logos are served one way ([00ea777](https://github.com/masksrb/masks/commit/00ea7771d2e22d20c04a9817d467d6d61a605c57))
* **server:** a suspension records its reason, and the idle sweep tells the mailer which warning to send ([84fd54b](https://github.com/masksrb/masks/commit/84fd54bd11557e3dabe2790d0b4f9eba3c670949))
* **server:** an unaccepted membership is never an owner, owner-only scopes live in one list, and memberships gain their columns in one migration ([9659d05](https://github.com/masksrb/masks/commit/9659d05d0d39a2090f71fb98ac395c4a3f4f61e1))
* **server:** emailed codes share the resend form, crowding check, and email confirmation with the flows before them ([901bfa9](https://github.com/masksrb/masks/commit/901bfa98ad7bdbb0052a17b8fed36651c71a4415))
* **server:** second factors finish through one helper, and code factors read one table per channel ([e617dc4](https://github.com/masksrb/masks/commit/e617dc4a2b9f8dabc2f9a04ac52a5db9745a9c57))
* **server:** the devices section is its own component, and a device lives under /people ([ebdfaf1](https://github.com/masksrb/masks/commit/ebdfaf15581bd7d888811b596fe833e8f389c8e5))
* **server:** the formatters pass on the secrets helper and the root lookup ([c74a8d1](https://github.com/masksrb/masks/commit/c74a8d1b673e0c469a2134314307b5132744199c))
* **server:** the manage console shares its tally, organization rows, and plurals, and asks only for the fields it shows ([e04576d](https://github.com/masksrb/masks/commit/e04576d20ac9fc88a9ce42df1542aa0878fca22d))
* **server:** the manage console's stylesheet names each colour, surface, and focus ring once, lists hold their slats through one class, and empty pages share one component ([9fb86a7](https://github.com/masksrb/masks/commit/9fb86a74d1cb3bd90a2d6a6d62a6c4313d3faa95))
* **server:** the person card renders once on the server, and the connect screen stops re-deriving what Client and the stylesheet already know ([209127e](https://github.com/masksrb/masks/commit/209127eb002fb31f998ecf4b42b4afed959c1507))
* **server:** the provider is the masks-server engine, and server/ mounts it ([baabad1](https://github.com/masksrb/masks/commit/baabad19b0bca65b5077c7e6644918aafdca871f))
* **server:** the setup token's length is checked with the rest of masks' configuration ([01c4bff](https://github.com/masksrb/masks/commit/01c4bfff084a099818e951defd5cf4b414d2d24f))

## [0.2.0](https://github.com/masksrb/masks/compare/server-v0.1.0...server-v0.2.0) (2026-09-13)


### ⚠ BREAKING CHANGES

* **server:** the thirty-six migrations before 1.0 are one migration now (ad0685c). A database that ran the old ones cannot migrate forward; dump what it holds, drop it, and let db:prepare load db/structure.sql.
* **server:** providers lose signs_in and provisions for role and trusts_email, and an issuer is required.
* **server:** /connections, /connections/token and the masks:connections:* scopes are gone, and connections hold no upstream tokens.
* **server:** the tenant's mail_from and smtp_* columns, and the matching updateTenant arguments and Tenant fields, are gone. Configure mail with createAdapter(service: "smtp") instead. The deployment-wide MASKS_MAIL_FROM and MASKS_SMTP_* settings still apply to a tenant with no mail adapter.
* **server:** the inviteActor mutation is gone. Callers move to createActor, whose email argument is no longer required.

### Features

* **client:** an app can act on a logout the issuer tells it about ([4d0b7f7](https://github.com/masksrb/masks/commit/4d0b7f77a74b0e416dda3e90413ad989a909f344))
* **client:** an app that delegates asks its handshake for masks:delegate: and the token exchange ([912e856](https://github.com/masksrb/masks/commit/912e856b00a9f27d59af861cdb35da518fa862bc))
* one palette across sign-in, the console and the docs ([20c5ee0](https://github.com/masksrb/masks/commit/20c5ee01274f6cba9f3d66b882a27236a6886830))
* **server:** a changed photo is confirmed by a green ring and check on the avatar that fade away ([3660591](https://github.com/masksrb/masks/commit/3660591c646e272ceac5c8d0ad8bbdebc58ea90c))
* **server:** a client hears about a sign-out it was part of ([a574959](https://github.com/masksrb/masks/commit/a57495961e1cbf70428ba98aebcea9c7aead6fd3))
* **server:** a client is edited and restored, and activity narrows to one subject ([bb24d0f](https://github.com/masksrb/masks/commit/bb24d0f7daf0818299e3fc3c29b8bb8212dff9a7))
* **server:** a client is told a subject of its own, and cannot correlate it ([8f65e3a](https://github.com/masksrb/masks/commit/8f65e3a91da32256c541165a118d62b7eebd4570))
* **server:** a client pushes its authorization request before sending anybody ([ca1c602](https://github.com/masksrb/masks/commit/ca1c602c785a8bc42cd68963e6606ae90aea83d6))
* **server:** a console shows the tokens still outstanding, and revokes them ([a7c7fef](https://github.com/masksrb/masks/commit/a7c7fefb91be8aa358404d32acc8e7ee12cf7a95))
* **server:** a console shows what somebody has allowed in and connected ([cb59f65](https://github.com/masksrb/masks/commit/cb59f654060210785bf2aecfc6c1c52e2e44bf99))
* **server:** a device with no browser is signed in from a phone ([809864b](https://github.com/masksrb/masks/commit/809864b5e77c927411af02c56199e5b2c7a2058f))
* **server:** a device you already signed out stops offering the button ([852236c](https://github.com/masksrb/masks/commit/852236ca68fb0c8a6ecba2e4ec54b7b9f68680e1))
* **server:** a first boot fetches authenticator metadata rather than seeding names ([f5fb0d6](https://github.com/masksrb/masks/commit/f5fb0d600181d984f3d7e4e868577bfb94339939))
* **server:** a manager blocks devices in bulk, by choosing them or by a fragment of their user agent ([9cb8845](https://github.com/masksrb/masks/commit/9cb8845edb0803e1c9eeec227398d0360c566a4c))
* **server:** a manager signs in with a second factor, and sets one up where they are asked ([fa3ddd9](https://github.com/masksrb/masks/commit/fa3ddd95fcc54e059481d8d0b2860be40dd5c668))
* **server:** a namespace can be released from the console ([87f68cc](https://github.com/masksrb/masks/commit/87f68ccb84a206c538cb386c81b762b2f366e967))
* **server:** a namespace is a grant, so an app can grow its own scopes ([0875440](https://github.com/masksrb/masks/commit/0875440bc37d8372395b3e206a053184aae50ec8))
* **server:** a namespace is claimed when a handshake is approved ([1161b35](https://github.com/masksrb/masks/commit/1161b3571a383936c3c9a772606a4a762f23f921))
* **server:** a new account is confirmed the way its policy says, and an existing one is asked for what the policy now needs ([e1d22ee](https://github.com/masksrb/masks/commit/e1d22eee503f484c8d220f265fac240c91a240a4))
* **server:** a new database is seeded with the authenticators masks ships ([e882c70](https://github.com/masksrb/masks/commit/e882c70c8607c5cc844a5af51bae2f783ce7132b))
* **server:** a provider either owns the account or is another way into one, and the sign-in policy decides where it is offered ([3c2e5dd](https://github.com/masksrb/masks/commit/3c2e5dd1aff98afb6b004f12036c6ca42894e433))
* **server:** a provider is set up from the console, not a rails console ([85471fc](https://github.com/masksrb/masks/commit/85471fc9c3affb27bae870e220662adf60872b9f))
* **server:** a SAML 2.0 identity provider signs people in ([d161bd0](https://github.com/masksrb/masks/commit/d161bd07344ae780afe1d304494b0ef930901bed))
* **server:** a scope is named in a word or two, not a sentence ([51ec7c8](https://github.com/masksrb/masks/commit/51ec7c8c454996abfd9760c3d6b18200a4932fb8))
* **server:** a sign-in policy says what somebody needs to sign in to a client, and whether they can sign up ([18c989e](https://github.com/masksrb/masks/commit/18c989ec2eca0bc4319b053416623e46307be51c))
* **server:** a sign-in shows what the server is doing at every step ([c4c2660](https://github.com/masksrb/masks/commit/c4c26600bfee79bc0108985657de24b1db26eb40))
* **server:** a tenant holds its own mailer, and changes it without a restart ([3e29b9a](https://github.com/masksrb/masks/commit/3e29b9a6363b08665ef4d8029c3c362d9c760976))
* **server:** a tenant says who may sign in, and the console stops shipping daisyUI ([b404a37](https://github.com/masksrb/masks/commit/b404a37daba93ef3fb8d86d2fa65f9ebc2180b4c))
* **server:** a tenant you pin serves every hostname ([5915963](https://github.com/masksrb/masks/commit/59159634e6640f0a17f4c8e9c803dfe3f52bbcca))
* **server:** a token is held to a key its client never sends ([0c97ab9](https://github.com/masksrb/masks/commit/0c97ab92e315d2f88243e85493be340ec9ea5335))
* **server:** an account is named by a nickname, an address, or either ([65419b2](https://github.com/masksrb/masks/commit/65419b2caf1ffffcb5d95e1407767b25e0945c55))
* **server:** an account is told by email what happens to it ([7d3f0dc](https://github.com/masksrb/masks/commit/7d3f0dc5089719e0f6f541a6f7e16d85da0b974e))
* **server:** an account reads as panels, and says what wants doing first ([effb20e](https://github.com/masksrb/masks/commit/effb20e45b17bdd6d486523f152ecccbbb1ef941))
* **server:** an app is listed by what it holds, and the insides match the outsides ([4e5b8c0](https://github.com/masksrb/masks/commit/4e5b8c09f14ddb675a1e954ce35cf53995e34b1c))
* **server:** an application is let use somebody's account elsewhere through a delegation ([4b7048c](https://github.com/masksrb/masks/commit/4b7048cb8ac4e174b9359a070b7a2d942a1c410d))
* **server:** an avatar is uploaded through the manage API ([6ef4db4](https://github.com/masksrb/masks/commit/6ef4db43e24b3cf96293fdcdbff78657c872cf6f))
* **server:** an empty instance goes to setup instead of describing itself ([028c186](https://github.com/masksrb/masks/commit/028c1861567743915b8c4ffb236b8633a913a3da))
* **server:** an empty instance says it is empty ([160b788](https://github.com/masksrb/masks/commit/160b788ec00d3a76caeef0423e0d3e82860d1190))
* **server:** authenticator metadata is refreshed on a schedule, not by hand ([9631c53](https://github.com/masksrb/masks/commit/9631c53eb2f4988fa6bb5717bc50fb4a9779678f))
* **server:** backup codes can be downloaded as a file where they are issued ([4616307](https://github.com/masksrb/masks/commit/46163072c14d943dae60859887ac7ca6418dcd53))
* **server:** configuration asks for the name and the mailer, and nothing else ([83ac6a8](https://github.com/masksrb/masks/commit/83ac6a83e9ac9bdb9f4c0febb622361e3ccac3c9))
* **server:** configuration is the installation's name and the URL it answers on ([0496442](https://github.com/masksrb/masks/commit/04964428754fc0a672f712d28c18e2a3c2b35a44))
* **server:** create actors from /manage, with or without a password ([59357e2](https://github.com/masksrb/masks/commit/59357e2c4b548204b378dcf0f39259b208660e34))
* **server:** devices have a page of their own, and activity narrows to one ([20e25dc](https://github.com/masksrb/masks/commit/20e25dc158150f63214f98d92b6b587f0d08553e))
* **server:** devices, so a session belongs to a browser you can name, trust or shut out ([09a9d4e](https://github.com/masksrb/masks/commit/09a9d4ee67d0b38b0779751ef368cfe6c89bb4c9))
* **server:** dynamic registration can be turned off ([079c53e](https://github.com/masksrb/masks/commit/079c53e482ed7519f129996460c028afa4a39c33))
* **server:** every consequential act is written down ([6d834aa](https://github.com/masksrb/masks/commit/6d834aa1a98396cf5f34449892bc29f3cf526488))
* **server:** every page carries the rose window as its icon, and the console wears it ([bec73c3](https://github.com/masksrb/masks/commit/bec73c3266b903411f6754f1683796ac357c0f7f))
* **server:** first-run setup and console pairing show the rose window ([17a45fa](https://github.com/masksrb/masks/commit/17a45fa1635d1d4cdcdff0f76d41424879f2f01c))
* **server:** five surfaces, so a grant never looks like a sign-in ([84123cb](https://github.com/masksrb/masks/commit/84123cb3714b4ab3f39705c0292d8799e1889dd7))
* **server:** mail and text messages go out through adapters a manager configures at runtime ([002b6b4](https://github.com/masksrb/masks/commit/002b6b4c30fa8c7ddb1b1e51c375272a95a7c12a))
* **server:** mail goes over SMTP, and is styled where it is read ([e5416c3](https://github.com/masksrb/masks/commit/e5416c39a6d71a5a8c5c08dedd017da65919309c))
* **server:** masks has a stained glass mark ([8fd7f74](https://github.com/masksrb/masks/commit/8fd7f74577e66daae8b448e4f1a739960079d7c9))
* **server:** masks no longer holds anybody's upstream tokens ([47a211b](https://github.com/masksrb/masks/commit/47a211bebfa77965ab1cb7c251b4d2f9149dce2b))
* **server:** one visual language across sign-in, /account and the console ([9127584](https://github.com/masksrb/masks/commit/912758443bb8eb61cfa2c780ed0de5484d272645))
* **server:** people and clients page past the first fifty ([54336b3](https://github.com/masksrb/masks/commit/54336b33b564a34b9b717f54bf21f6b8c3215a23))
* **server:** people narrow to the invited and the privileged, and every namespace is listed ([49805de](https://github.com/masksrb/masks/commit/49805de0c866d4394a1e55c08901d39b5cce2933))
* **server:** people, avatars, and one page instead of three ([e3d544f](https://github.com/masksrb/masks/commit/e3d544f04e338ec145789bbb828c3c299ceccf94))
* **server:** plain oauth2 providers, apple, presets for the common ones, and linking a provider from the account page ([974cc21](https://github.com/masksrb/masks/commit/974cc212cdc1fd0a527a6e4ab17072dc3ffbe819))
* **server:** setting up confirms the password before it creates the owner ([6c604ea](https://github.com/masksrb/masks/commit/6c604ea303e7727ab98a2c8cc9c34702136d9695))
* **server:** signing up is one flow that follows the sign-in policy, and first-run setup is signup for the first account ([93d39f5](https://github.com/masksrb/masks/commit/93d39f53501f0c33997fcd3a4863c14e2d3d94f2))
* **server:** somebody signs in with a provider, not only connects one ([a4ead6b](https://github.com/masksrb/masks/commit/a4ead6b006e0a1859993e5c2a780043a68aede0b))
* **server:** the account page follows the reference it was given ([43488d2](https://github.com/masksrb/masks/commit/43488d2af95c89742c7bcadd041f65c5eb5444ee))
* **server:** the account page reads like an account page ([186247f](https://github.com/masksrb/masks/commit/186247f7a273139838dc507608fabc8f04953719))
* **server:** the account, mail and refusal screens read from a locale file ([0d1b8b6](https://github.com/masksrb/masks/commit/0d1b8b614bf0c1e901c4e86b7e0ef26ae6805f91))
* **server:** the console adds a provider from a preset, and the docs explain providers end to end ([f14837a](https://github.com/masksrb/masks/commit/f14837a5d4e601c658e2b0b2775b59283adb4f65))
* **server:** the console nav is overview, people, devices and clients, with settings behind the manager's avatar ([641cf3f](https://github.com/masksrb/masks/commit/641cf3f23acbf4d328f5ff65c92076715ae52ab1))
* **server:** the first-run screen takes a name as well as a nickname ([1e36707](https://github.com/masksrb/masks/commit/1e36707e8041492e5a04fe7fafa77e60f3d2820b))
* **server:** the identities scope tells an application which accounts elsewhere somebody signs in with ([164c832](https://github.com/masksrb/masks/commit/164c8329c1843fba3d1cc926a7ac1f56ef68f537))
* **server:** the last tab asks what this installation is called, and what apps may register for ([4dfa926](https://github.com/masksrb/masks/commit/4dfa926f6d3604caff112c79ff60d0ad8b99c22a))
* **server:** the login machine speaks the reader's language ([f7a7587](https://github.com/masksrb/masks/commit/f7a75875cd8c03e10fd572ff9f38be1a809c3e22))
* **server:** the mark is a flat rose window ([ba8a3fc](https://github.com/masksrb/masks/commit/ba8a3fc4a37bdce8363feee2900f19122e37346e))
* **server:** the mark is a golden stained glass mosaic, edge to edge ([4038885](https://github.com/masksrb/masks/commit/40388854055875eef9e0b90c5e4047bf04c162b5))
* **server:** the mark is flat, touching shards under a drifting light ([ea4161e](https://github.com/masksrb/masks/commit/ea4161e5895235b2540473983edd79f12f6cc3ae))
* **server:** the mark is traced from a real rose window ([5ea2953](https://github.com/masksrb/masks/commit/5ea295376a31c8e545fbb3565ddf4c6a914dc1e6))
* **server:** the rose window turns ([5d70670](https://github.com/masksrb/masks/commit/5d7067076da136f54a02aeea10d283646f0cf71c))
* **server:** the scopes on offer include the ones this server publishes ([e473a45](https://github.com/masksrb/masks/commit/e473a4577b0948804924cdef9e73a6cfbae064d2))
* **server:** the sign-in screens are grey, and setup earns its colour ([ad7dce2](https://github.com/masksrb/masks/commit/ad7dce222b15bb9d1515fbf15ef4dcb38c2101f6))
* **server:** the source reloads when it runs in a container ([2e7480a](https://github.com/masksrb/masks/commit/2e7480a88abbaa2019171aee076dfde2b43e9702))
* **server:** the whole dev stack runs from one command and one compose file ([fe14d51](https://github.com/masksrb/masks/commit/fe14d51e5a8a07439dd6b59bbab15b78f0210a87))
* the server is published as a container image ([16630a8](https://github.com/masksrb/masks/commit/16630a8e71c5244e404d4f7d7a3a8dc016117eb2))


### Fixes

* **dev:** background jobs run on the host, not only inside the container ([24369d2](https://github.com/masksrb/masks/commit/24369d2a59b96efbbaa598f9b6b28a5b2ea60a18))
* **server:** a client pushing over basic auth need not repeat its id ([9750224](https://github.com/masksrb/masks/commit/9750224fd0be3c227e154f019282970e7821276b))
* **server:** a client stops reading tokens by declaring somebody else's resource ([8b9b877](https://github.com/masksrb/masks/commit/8b9b877c4d91a2673dd11a12f63ca4abb2f68681))
* **server:** a database built before the migrations were collapsed is refused with a way forward ([429fb11](https://github.com/masksrb/masks/commit/429fb11fc23f72ba6f9c52fb046c37e3cb79e8ed))
* **server:** a device is signed in only by somebody who said yes to it, never by following a link ([f21cfe8](https://github.com/masksrb/masks/commit/f21cfe8290b6cf57bd6fc302c5e3432a6351bba7))
* **server:** a job invoked in process is not refused for having no envelope ([2510b3e](https://github.com/masksrb/masks/commit/2510b3e76641378b4673117cff9f19bfab26e82b))
* **server:** a job reads its tenant from its own envelope, not from the thread ([9fa8dcb](https://github.com/masksrb/masks/commit/9fa8dcb16738ae9cc946f6063bd5a97b4875495d))
* **server:** a login that remembers an account the database no longer has starts over instead of redirecting forever ([0c6c1c7](https://github.com/masksrb/masks/commit/0c6c1c740ded22e6dfd055e4630088b9a84919a6))
* **server:** a logout hint ends only the session of the person it names ([d84a6b4](https://github.com/masksrb/masks/commit/d84a6b428be546f38aacc5d70780c2e405d65987))
* **server:** a logout no client ever answered is written down ([b26defe](https://github.com/masksrb/masks/commit/b26defe89f58d7fe57822895dcccfd95a275f263))
* **server:** a notice on the account page sits under its title in the page's own colours, and the current device reads "This device" ([268a522](https://github.com/masksrb/masks/commit/268a5222bd22da529f31c8dba01b299615eaa2d2))
* **server:** a one time password is spent by the sign-in that used it ([9555716](https://github.com/masksrb/masks/commit/9555716aa307ba885824bfad284b0d616a93ecdb))
* **server:** a pushed request names its client, whatever it authenticated with ([0ae893a](https://github.com/masksrb/masks/commit/0ae893af99bd78d3c296a82a5e87537b4b91f463))
* **server:** a re-authentication names the person who just proved themselves ([4c87358](https://github.com/masksrb/masks/commit/4c87358ca2a6caf209403ab19750a0acb9e84762))
* **server:** a refused password is said in red under the password field, and every password follows the sign-in policy ([daa65ea](https://github.com/masksrb/masks/commit/daa65ea984ea490c6b8d8e7d6add77ed424f6c3a))
* **server:** a replayed refresh token takes its whole family down ([02f08ca](https://github.com/masksrb/masks/commit/02f08caa8ec68c4e419dfaa8132a192f2b40ab95))
* **server:** a request_uri is spent only by the client that pushed it ([55e6769](https://github.com/masksrb/masks/commit/55e67697f799a7fa11b3b7166786f14894d54449))
* **server:** a second factor proved by one account stops satisfying another's ([74f18fd](https://github.com/masksrb/masks/commit/74f18fdaf6325a69193b3b55ac68c03190fa3c03))
* **server:** a self-registered client is not called inside the network ([dcb510c](https://github.com/masksrb/masks/commit/dcb510cbe3c168efce8577bc25e786146db2033c))
* **server:** a switch refuses a database role that sees past row-level security ([40d9668](https://github.com/masksrb/masks/commit/40d96686fbb19b37ffbbdaa75bc33dd6da28e13d))
* **server:** a tenant is named exactly what it was declared ([d3f3b9f](https://github.com/masksrb/masks/commit/d3f3b9f3ebb5d2ce4383af3a722e1fb55476fb6d))
* **server:** a token endpoint stops naming resources the authorization never carried ([0d66ee4](https://github.com/masksrb/masks/commit/0d66ee458a794cbe09a8c43a3b8405591c8f7e86))
* **server:** a used confirmation code stays used, and racing guesses all count ([531a80a](https://github.com/masksrb/masks/commit/531a80a3acd218f122af74c587bb45ef49692017))
* **server:** an address belongs to one account ([3864bf0](https://github.com/masksrb/masks/commit/3864bf056bb0cf367c3b4c5ba5a94bd9309b7749))
* **server:** an allowed domain is one the provider actually confirmed ([121ce96](https://github.com/masksrb/masks/commit/121ce96c40fe5dbe2d64410239a920fcac8f6c23))
* **server:** an outbound call goes to the address that was checked, and stops reading at the ceiling ([779fae4](https://github.com/masksrb/masks/commit/779fae4510b634d217c8af14887ac736e0029b11))
* **server:** an upstream identity reaches an account only by proving it ([481073c](https://github.com/masksrb/masks/commit/481073ce9c99ae98b20dff8eb55f51fc7ac178f0))
* **server:** approving a client is the approver's consent, not everybody's ([119c347](https://github.com/masksrb/masks/commit/119c34739d4adb1ab74663f71a0ca5bbbe63e356)), closes [#83](https://github.com/masksrb/masks/issues/83)
* **server:** approving an application takes a scope of its own ([7adc1bc](https://github.com/masksrb/masks/commit/7adc1bc5d45b26f71ba70671e0906b2af5cc7db6))
* **server:** asking for a passkey no longer overflows the session cookie ([ce00180](https://github.com/masksrb/masks/commit/ce001809056e9bca2058b7fb1fbf66b39d4a1d4e))
* **server:** booting the dev stack prepares only the development database ([4b4bec4](https://github.com/masksrb/masks/commit/4b4bec4d3de02b2d6147c413ce5a4f75a5999804))
* **server:** containers sharing a node_modules volume install one at a time ([446623a](https://github.com/masksrb/masks/commit/446623a0c5ba1e76de7512240ad1918357ba682e))
* **server:** every setup field turns green when it is filled ([669f397](https://github.com/masksrb/masks/commit/669f3976c71e87d995dd6bbab8519db7295a3162))
* **server:** masks registers with an MCP server as a confidential client whenever the server takes a secret ([5435b00](https://github.com/masksrb/masks/commit/5435b00ec3c4c5a1a7a7deaf11ca529785a4444d))
* **server:** revoking a refresh token also ends the access tokens its grant issued ([a0ddbc9](https://github.com/masksrb/masks/commit/a0ddbc9fbeca1a09805c158132fd3d9223911961))
* **server:** setup and signup ask for a name first ([76ce27d](https://github.com/masksrb/masks/commit/76ce27db77cd1c62c5f25d25a3b1a0db0b474c74))
* **server:** setup stops explaining the name field ([82ee33f](https://github.com/masksrb/masks/commit/82ee33f509f5104ded079daa1438aba92ef1bd5a))
* **server:** stopping one delegation leaves another to the same provider working ([3f375e3](https://github.com/masksrb/masks/commit/3f375e37c1386e9408fc54144fd57943390b61d8))
* **server:** the activity log pages by cursor, not by timestamp ([2c8d7a7](https://github.com/masksrb/masks/commit/2c8d7a7c8ec5bec7a9a2f7e701efcf69df8e5873))
* **server:** the adapters migration runs on a database whose mail columns are already gone ([247d667](https://github.com/masksrb/masks/commit/247d667fab830eac24e3c1497c02cd31c8526db1))
* **server:** the console and account page work on a phone ([33817e6](https://github.com/masksrb/masks/commit/33817e63f4b46a7fd7ba8c29a0010df767cd5fbd))
* **server:** the console is Helvetica, and a badge grows to fit its label ([6e70fd7](https://github.com/masksrb/masks/commit/6e70fd7f9faf907aa9cf9bca34976b3340de4440))
* **server:** the console's avatar link is named for a screen reader again ([c8cdc84](https://github.com/masksrb/masks/commit/c8cdc848adf40f468fd28725c4513ea8fa41da99))
* **server:** the first-run heading gets room under it ([f31fdc0](https://github.com/masksrb/masks/commit/f31fdc0cdf245d5a00f6b1dd4db849df86c2b377))
* **server:** the image builds again, and a derived avatar is not shared ([a919e5a](https://github.com/masksrb/masks/commit/a919e5aaf2da75bcb7e9c7c3b3629f9bc4f87546))
* **server:** the manage API passed a value-returning callback to forEach ([b38cef4](https://github.com/masksrb/masks/commit/b38cef4ea8339b7df6aa6dda7735ef46727269b5))
* **server:** the optional name on setup turns green when it is filled too ([aec5bc3](https://github.com/masksrb/masks/commit/aec5bc377c89ce172d811d0a2c3cd31ef4cbf360))
* **server:** the origin is configuration, and approval decides where a client lives ([b19a66c](https://github.com/masksrb/masks/commit/b19a66c3d5b1f2941ecc2df8c2e917f39ccdbb4d))
* **server:** the people who run a server are called managers everywhere ([10b653e](https://github.com/masksrb/masks/commit/10b653edecfc978a35e93d79bd05b0dbbc4df3fd))
* **server:** the rose window holds still ([29e9e30](https://github.com/masksrb/masks/commit/29e9e30c4501d2353258d71dd7816a86e6f4e751))
* the test tasks live where every other rake task does ([003faaf](https://github.com/masksrb/masks/commit/003faaff8a85b0180ffa9102d1c835a36205a6f6))


### Performance

* **server:** the suite stops generating an RSA key it never reads ([6b65fc2](https://github.com/masksrb/masks/commit/6b65fc25bc21f734ba96856b3cd3b3cae10ac089))


### Documentation

* masks calls each thing by one name, and the words reference says which ([97847c3](https://github.com/masksrb/masks/commit/97847c307b375e28aa6cbca0a1dbc04b338c1cd7))
* READMEs that match the code, and a server one that is not the scaffold ([e0148e1](https://github.com/masksrb/masks/commit/e0148e14e0092731bcd095bc0fc22a1589c3acc0))
* references are generated from the code that defines them ([ba74550](https://github.com/masksrb/masks/commit/ba745501e651b797948e5abd5640a1825616100c))


### Refactoring

* comments are gone; the code says what it does ([0fc8e6a](https://github.com/masksrb/masks/commit/0fc8e6a4692e3f09831514b6d167c3e23d7db419))
* **db:** one migration creates the schema ([ad0685c](https://github.com/masksrb/masks/commit/ad0685c861990d21cd0f5279529d8ded65521d9a))
* every suite is named for what it proves, under one test directory ([315b371](https://github.com/masksrb/masks/commit/315b371e64baa4441014669744a61c88341d27c7))
* one command owns the repo, and CI runs in the order it should ([161f823](https://github.com/masksrb/masks/commit/161f823ac64dd40bf305ddb066803a00f9ed97ea))
* rename the example tenant from jons to demo ([aef32a6](https://github.com/masksrb/masks/commit/aef32a670b4b3c696089c07bf15103e1d981eb00))
* **server:** a lines field seeds its draft without tracking the prop ([fcc86c1](https://github.com/masksrb/masks/commit/fcc86c1957537579b75d0c6f719358ce6e8eb3aa))
* **server:** a login answers only up to the state that prompts, and the rest of the review's cleanups land ([37c5def](https://github.com/masksrb/masks/commit/37c5def1132319b7f8911557fe1f682ffd084a18))
* **server:** a login in progress is held on the server, and the cookie carries only a reference to it ([9362201](https://github.com/masksrb/masks/commit/93622014876c12ac2d35457e6319e225d97a3cec))
* **server:** a tenant is entered once, at the edge, and carried the rest of the way ([1a7618b](https://github.com/masksrb/masks/commit/1a7618b01814340a0a757a2f6efa7eb3a8215a61))
* **server:** delegation shares what sign-in and linking already had, and asks the database less ([44b8c4d](https://github.com/masksrb/masks/commit/44b8c4d303dfcc6de60f98d7824c544bd67e347c))
* **server:** signup, confirmation and adapters share one description of each thing instead of several ([431e83f](https://github.com/masksrb/masks/commit/431e83f197d34dc54e923b369ddde5170e754285))
* **server:** the backup code task retires, as the manage API generates them ([bf34ebe](https://github.com/masksrb/masks/commit/bf34ebeebbd16247d89aa849f2ca4c51737926b4))
* **server:** the three new grants stop repeating themselves ([8e16317](https://github.com/masksrb/masks/commit/8e163172b6c57645f307a036cf858838bb8c4fab))
