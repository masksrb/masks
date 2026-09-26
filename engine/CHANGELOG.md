# Changelog

## [0.3.0](https://github.com/masksrb/masks/compare/masks-server-v0.2.0...masks-server-v0.3.0) (2026-09-26)


### ⚠ BREAKING CHANGES

* **server:** the icons are served at /masks-public/icon.svg, /masks-public/icon.png, and /masks-public/favicon.svg. SMTP settings apply to masks' own mailer, not ActionMailer::Base.
* **server:** job classes in recurring.yml and anything naming a provider class are now Masks::Server::*.

### Features

* **server:** a passkey on the second factor screen trusts the device when asked to, and an account holding a passkey alone is offered the trust box ([e079aa2](https://github.com/masksrb/masks/commit/e079aa28a8fff0f9152ed610b45177576e46fd05))
* **server:** a public app that is already approved and allowed pairs again without the approval screen ([c408cd2](https://github.com/masksrb/masks/commit/c408cd2e10d7cdb3846b3aac37aecc67d3cc1421))
* **server:** a second factor screen that can offer nothing says the sign-in cannot continue, and names what settles it ([6d31d65](https://github.com/masksrb/masks/commit/6d31d65787df2e4a3c50000f3f817433c5d8b417))
* **server:** a sign-in can be approved from a device you trusted, by entering the code it shows ([1c133e6](https://github.com/masksrb/masks/commit/1c133e6183167e6bc077e2b522d674b0b2815bee))
* **server:** a sign-in can be confirmed with a code sent by email or text message ([1097356](https://github.com/masksrb/masks/commit/1097356464a903478c74017591e92ac79a679a17))
* **server:** a signed-out visit to the account page goes straight to sign-in, which asks you to sign in to continue ([1158748](https://github.com/masksrb/masks/commit/115874896a5de797116928db5432024ae80ed1ff))
* **server:** manage lays its sections straight onto the page, with no card around them ([22c6e84](https://github.com/masksrb/masks/commit/22c6e8482e2b412095a7d4e87c21839ef062e41e))
* **server:** masks mounts inside another Rails app, in engine mode ([103751f](https://github.com/masksrb/masks/commit/103751fe4f78f084ffe1643fab3eb9ec464d56c4))
* **server:** the connect screen asks one fixed question and says the rest in a line ([230afad](https://github.com/masksrb/masks/commit/230afad6a84bbc920d47b74e86e455cec93fc427))
* **server:** the consent screen shows who is signing in under its heading, as the connect screen does ([22391b0](https://github.com/masksrb/masks/commit/22391b01256aaf3404d1469c6e5d9d6cf23a1d76))


### Fixes

* **server:** a provider may point at a name under .localhost over plain http, as an application's redirect already may ([c2690f6](https://github.com/masksrb/masks/commit/c2690f6677710e5eb87b7ac5e249cd7d3126444b))
* **server:** a resource whose metadata could not be read is asked again at the next sign-in ([1de66ee](https://github.com/masksrb/masks/commit/1de66eec4ac0037c965b708aadca4dffd5fded9a))
* **server:** allowing an app back in after cutting it off from the account page no longer fails ([d22a2c4](https://github.com/masksrb/masks/commit/d22a2c45c5afcb19a720edfa70e1482592be7d0a))
* **server:** the provider's own jobs carry their tenant, and nothing else's do ([59a1b59](https://github.com/masksrb/masks/commit/59a1b595bc0a133967bd891374fa127dd34e1d24))


### Refactoring

* **server:** the provider is the masks-server engine, and server/ mounts it ([baabad1](https://github.com/masksrb/masks/commit/baabad19b0bca65b5077c7e6644918aafdca871f))
* **server:** the setup token's length is checked with the rest of masks' configuration ([01c4bff](https://github.com/masksrb/masks/commit/01c4bfff084a099818e951defd5cf4b414d2d24f))
