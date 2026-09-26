# The second factor screen

Every account that reaches the second factor screen is offered a factor it can use, and the screen
says so when it can offer none.

Written 2026-09-21, after `b4fcce4` and `9959322`. Both phases are usable on their own.

Background: `b4fcce4` made the heading name the factor the screen offers, because
`second-factor.svelte` asked for a code on accounts that hold a passkey and no authenticator app.
`9959322` made a refused passkey report itself, because WebAuthn returns `NotAllowedError` both for
a dismissed dialog and for a device that holds no credential, and the button treated every refusal
as a dismissal. A review of those two commits recorded the two gaps below.

## Decisions still open

- [ ] **Does a passkey trust a device?** Trusting a device skips the second factor for
      `DeviceFactor::LIFETIME`. A passkey already proves the device holds a credential the account
      registered, so the trust it buys differs from the trust an authenticator app code buys.
      Phase 1 assumes a passkey trusts a device on the same terms. Deciding otherwise keeps the
      checkbox with the code form, and accounts holding a passkey alone never see it.

## Phase 1 — trust survives the passkey path

`second-factor.svelte` keeps the trust checkbox inside the block it renders for `methods.otp`, so
an account holding a passkey and no authenticator app never sees it, while `SecondFactor#as_json`
sends `rememberable` as `device.present?` for either factor. An account holding both factors sees
the checkbox, checks it, signs in with a passkey, and loses the check:
`LoginStates::OneTimePassword` accepts `:remember` and calls `remember!` when the device is
present, and `LoginStates::Passkey` accepts `:passkey` alone and calls `factored!` without
`remember!`.

- `LoginStates::Passkey` accepts `:remember` and remembers the device on its second factor path,
  under the same `device.present?` condition `OneTimePassword` uses.
- `PasskeyButton` carries the checkbox's value on `passkey:verify`.
- The checkbox moves out of the `methods.otp` block, so every account `rememberable` covers sees
  it.

## Phase 2 — a screen that offers nothing says so

Three conditions each hide one way through the screen. The code form renders for `methods.otp`.
`PasskeyButton` renders for `offered && available()`, and `available()` is `supported()` from
`@github/webauthn-json`, which is false wherever `window.PublicKeyCredential` is absent, including
a page served over an origin the browser treats as insecure. The backup code action renders for
`login.backupCodes`, which `BackupCode#enabled?` ties to `actor&.backup_codes?`. An account whose
only second factor is a passkey, holding no backup codes, on such an origin, reads the heading and
the identified row alone, and the heading names a factor the screen cannot offer.

- The screen says that it cannot continue, and names what settles it.
- `halted` and `halted_lede`, which `Login.svelte` renders for a login that cannot go on, are the
  pattern to follow.

## Verification

- An account holding a passkey and an authenticator app checks the trust box, signs in with the
  passkey, and reaches the next sign-in from that device without a second factor.
- An account holding a passkey alone is offered the trust box, and the same holds.
- An account holding a passkey alone and no backup codes, served where
  `window.PublicKeyCredential` is absent, reads why the screen cannot continue.
- `./dev test` passes.

## Known gaps, recorded rather than fixed

From a security review of `138628a`, which moved tokens and adapters off stored class names. The
review found nothing exploitable, and the change closes the constant lookup Rails performs on a raw
inheritance column. These three notes are what it left behind.

- **`find_sti_class` drops the containment check.** `Token.find_sti_class`
  (`server/app/models/token.rb:40`) resolves through the frozen `KINDS` hash and
  `Adapter.find_sti_class` (`server/app/models/adapter.rb:72`) through the explicit `services` list,
  and each raises `ActiveRecord::SubclassNotFound` otherwise, so neither reaches a constant lookup on
  a value a caller supplies. Rails also checks that the class it resolves is the querying class or one
  of its descendants, and both overrides leave that out, so `AccessToken.find_sti_class("password_reset")`
  answers `PasswordReset`. Nothing reaches it today: the value comes from the inheritance column,
  `ensure_proper_type` writes that column from `sti_name`, every read on a subclass carries the STI
  condition, and no token is built from caller attributes anywhere in `server/app` or `server/lib`. A
  creation path that accepts attributes makes the check worth restoring.

- **`138628a` asks for a rebuilt database.** It edits `20260912000000_create_masks_schema` and
  `20260913000000_create_adapters` in place and says so in a `BREAKING CHANGE:` trailer. A database
  that already recorded those two versions keeps its `type` column and raises `PG::UndefinedColumn` on
  the first token the server reads, which is loud and immediate.

- **A demodulized name decides a stored kind.** `Token.sti_name` (`token.rb:36`) keys `KINDS` by
  `name.demodulize`, and `Adapter.service` (`adapter.rb:39`) uses `name.demodulize.underscore`, so
  stored values survive the move of `server/app` under `Masks::Server`, and
  `module_parent.const_get(class_name, false)` resolves against the namespace the subclasses land in.
  Two `Token` subclasses sharing a demodulized name in separate modules would collapse onto one stored
  kind. No two share one today.
