# Known gaps

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
