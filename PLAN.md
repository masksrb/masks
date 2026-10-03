# Plan

What is left to build, and the gaps known in what is built. The public version of the enterprise
plan is [guides/enterprise](docs/src/content/docs/guides/enterprise.mdx), and its status lines change
when a capability lands.

## To build

### Rich authorization requests

- `authorization_details` (RFC 9396) on `/authorize`, pushed requests, and token exchange. Each
  client declares the `type` values it accepts and a JSON schema for each.
- The consent screen lists each detail with a label from the client's declaration.
- Granted details go in the access token and in the introspection response.

### Migration

- A `masks:import` runner reads a file and creates accounts in batches of 500 inside
  `Tenant.switch`, recording one `account.imported` event per batch.
- Formats: Auth0's bulk export (bcrypt hashes, which masks verifies directly), Firebase's
  `auth:export` (modified scrypt with the project's hash parameters), and a generic JSON with
  `algorithm`, `hash`, and `salt`.
- `actors.legacy_password`, encrypted, holds the algorithm and parameters. `Actor.authenticate`
  tries it when `password_digest` is blank, then writes a bcrypt digest and clears it.
- Okta and Cognito do not export hashes. A `legacy_providers` record holds a verification endpoint
  (Okta's authentication API, or a Cognito user migration Lambda URL). On a first sign-in with no
  digest, masks checks the password there through `Outbound`, stores its own digest on success, and
  never asks again. Manage shows how many accounts still depend on it.
- Emails are marked verified only when the export says so.

### Shared signals receiver

`/ssf/events` accepts security event tokens from a provider, verifies them against the provider's
JWKS, and ends the sessions of the matching connection's account.

### Follow-ups

- Shared signals transmitter: `account-purged` (captured before the account is destroyed), the add
  and remove subject endpoints, poll delivery, and a manage view of each client's stream.
- Custom domains: mail sent from the tenant's domain once its SPF and DKIM records are in place.
- Home-realm discovery: `login_hint` sent to the provider, and a policy that forbids falling back to
  a password for a proven domain.
- Manage roles: the console hides each action the viewer's level cannot take.
- Organizations: per-organization admin roles below `owner`.

### Rules for every capability

- Migrations get row-level security, and `server/db/structure.sql` is regenerated in the dev
  container. The diff contains only the new tables or columns.
- Manage API changes come with the Svelte page, integration tests, and a regenerated reference.
- Anything that calls out from masks goes through `Outbound`, so private addresses are refused.
- Every new action gets an `Event` constant, a label in `engine/config/locales/en/events.yml`, and a
  decision on whether it belongs in `Event::GRAVE` or `Notifications::GROUPS`.

## Known gaps

- **`find_sti_class` drops the containment check.** `Token.find_sti_class`
  (`engine/app/models/masks/server/token.rb`) resolves through the frozen `KINDS` hash and
  `Adapter.find_sti_class` (`adapter.rb` beside it) through the explicit `services` list, so neither
  reaches a constant lookup on a value a caller supplies. Rails also checks that the resolved class
  is the querying class or one of its descendants, and both overrides leave that out, so
  `AccessToken.find_sti_class("password_reset")` answers `PasswordReset`. Nothing reaches it today:
  the value comes from the inheritance column, which `ensure_proper_type` writes from `sti_name`, and
  no token is built from caller attributes. A creation path that accepts attributes makes the check
  worth restoring.
- **A demodulized name decides a stored kind.** `Token.sti_name` keys `KINDS` by
  `name.demodulize`, and `Adapter.service` uses `name.demodulize.underscore`. Two `Token`
  subclasses sharing a demodulized name in separate modules would collapse onto one stored kind. No
  two share one today.
