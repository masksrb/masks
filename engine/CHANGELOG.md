# Changelog

## [0.4.0](https://github.com/masksrb/masks/compare/masks-server-v0.3.0...masks-server-v0.4.0) (2026-10-04)


### Features

* **engine:** a client_id that is the https URL of a client metadata document signs people in without registering first, as MCP clients do ([86dd5b6](https://github.com/masksrb/masks/commit/86dd5b61adf51f2dc0c294777eb2ed4af6fec5f7))
* **engine:** a consent remembers the authorization details a declared type allows, and a client's consents can expire ([bdfc149](https://github.com/masksrb/masks/commit/bdfc1496fe9f0a8df2aec8becb4b9637f23b200c))
* **engine:** a person downloads everything masks holds about them as a JSON file from their account page ([bc1b729](https://github.com/masksrb/masks/commit/bc1b72995a07ba43d518a10fbac2ae71fcba6c26))
* **engine:** an owner rewords the subject and opening of the invitation, reset, confirmation, code, and approval emails, and adds a signature to every email ([eb74a02](https://github.com/masksrb/masks/commit/eb74a023994628f1a19cce6e12d822e17ef1181e))
* **engine:** masks receives shared signals at /ssf/events, and a provider that revokes a session or disables an account signs that person out here ([7e627fe](https://github.com/masksrb/masks/commit/7e627fe62734c1356f56c1913f7ff45988044848))
* **engine:** MASKS_OUTBOUND_ALLOWED names private ranges masks may call, for apps on a private network such as a tailnet ([ed1a829](https://github.com/masksrb/masks/commit/ed1a82919ac7f74b9c43cee7381b04b6aae239a3))
* **engine:** rich authorization requests (RFC 9396) carry authorization_details from /authorize to the token, checked against types an approved client declares ([18dc29a](https://github.com/masksrb/masks/commit/18dc29a985b67b95e2e682b87a8a29829607a735))


### Fixes

* **engine:** a self-registered client cannot name resources, so it cannot have tokens addressed to another service ([39e186d](https://github.com/masksrb/masks/commit/39e186d38abc2c9a2b56483ef6c993d74d2c0905))
* **engine:** providers, SMS adapters, and resource metadata are called through Outbound, so a private address is refused there too ([20f8d2d](https://github.com/masksrb/masks/commit/20f8d2d9b2a18490128abfefa2cb76c74825a996))
* **engine:** state joins a query the registered post_logout_redirect_uri already carries, instead of a second question mark breaking the address ([c639a6b](https://github.com/masksrb/masks/commit/c639a6b94379a775f035a09268dc5bb3bdc2cc20))
* **server:** acr_values is read as a list of acceptable values, so a request that also accepts a password is not stepped up to a second factor ([ecaba6a](https://github.com/masksrb/masks/commit/ecaba6a97bc50f93c4ccbe89ab4df8681f21c04b))


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
