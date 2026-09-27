# Enterprise plan

The public version of this plan is [docs/src/content/docs/guides/enterprise.mdx](docs/src/content/docs/guides/enterprise.mdx).
This file adds the build order, what the code already has, the implementation steps, and the state of
the work.

`PLAN.md` holds an unrelated list of known gaps, so this plan has its own file.

## State

| Capability | State | Commit or next step |
| --- | --- | --- |
| Audit log | Built | `Event`, about 100 actions, 180-day retention |
| Event streaming | Built | `03b525c`, `bbe2ea1`, guide at `guides/event-streams` |
| Single sign-on and provisioning | Built | OIDC, OAuth, SAML in and out, SCIM |
| Step-up authentication | Built | `a6fd2fe`. A policy cannot require a level yet (see [Policy-required step-up](#policy-required-step-up)) |
| Token exchange | Partly built | RFC 8693 is built. Exchanges are not audited, and RFC 9396 is missing |
| Manage roles | Not started | |
| Organizations and roles | Not started | |
| Home-realm discovery | Not started | |
| Session policies | Not started | |
| Audit export and retention | Not started | |
| Adaptive risk | Not started | |
| Passwordless email | Not started | |
| Custom domains | Not started | |
| Shared signals | Not started | |
| Migration | Not started | |

## What the code already has

Checked against the code on 2026-09-27. Each planned item starts from these.

- **Token exchange.** `Exchange` implements RFC 8693: access and ID tokens as the subject, actor tokens,
  a nested `act` chain, and upstream tokens released through `Delegation`. `TokensController` issues
  the token and records no event.
- **Provider domains.** `Provider#email_domains` and `#welcomes?` restrict who a provider admits.
  `ProviderDomains.join` normalizes the list. Nothing routes an address to a provider by its domain,
  and nothing proves a tenant owns a domain.
- **Tenant resolution.** `Tenant.resolve(host)` takes the first label of the host, or the pinned
  tenant. `Tenant#public_origin` formats `public_origin_template` with the subdomain. A custom domain
  needs both to learn a second lookup.
- **Manage access.** `masks:manage` is one scope. Anyone holding it can do everything manage does.
- **Sessions.** `Session::LIFETIME` is a fixed 14 days. No sign-in policy changes it.
- **Passwords.** `has_secure_password` with bcrypt, a decoy digest against timing, and a common
  password list at `config/passwords/common.txt`. No breach check.
- **Factors.** `SignInPolicy::FIRST_FACTORS` is `password passkey provider`. Email and SMS codes are
  second factors only.
- **Audit log.** `Event::RETENTION` is a fixed 180 days, enforced by `CleanupJob`. Manage pages through
  events and has no export.
- **Outbound calls.** `Outbound` refuses private addresses, caps bodies, and times out. Everything new
  that calls out uses it.

## Order

Sizes: S is a day, M is two to four days, L is a week or more.

| # | Capability | Size | Depends on | Why here |
| --- | --- | --- | --- | --- |
| 1 | Token exchange events and policy-required step-up | S | | Finishes two partly built items |
| 2 | Manage roles | M | | Enterprise buyers ask for least privilege in the admin console before anything else |
| 3 | Organizations and roles | L | 2 | Everything per-customer builds on it |
| 4 | Home-realm discovery | M | Domain proof | Makes SSO usable without a per-customer sign-in link |
| 5 | Session policies | S | | Common compliance ask, small change |
| 6 | Audit export and retention | S | | SOC 2 evidence and regulated retention periods |
| 7 | Adaptive risk | M | 1 | Reuses step-up |
| 8 | Passwordless email | M | | Consumer and low-friction B2B markets |
| 9 | Custom domains | L | Domain proof | Needs certificates and a second tenant lookup |
| 10 | Shared signals | M | Event streams | Reuses delivery and signing |
| 11 | Rich authorization requests | M | 1 | Finishes token exchange |
| 12 | Migration | L | | Adoption, and Okta and Cognito need a live check against the old provider |

Domain proof is shared by 4 and 9, so it is built once with 4.

Each capability is its own commit or series of commits, with tests, docs, a regenerated reference
(`./dev reference`), and a `structure.sql` diff that contains only its own tables.

## Implementation

### Token exchange events

- Add `Event::EXCHANGE_GRANTED` and `Event::EXCHANGE_REFUSED`, with labels in `events.yml`.
- `TokensController` records a grant after `Exchange#issue!`, with the client, the actor, the granted
  scopes and audience, the requested token type, and the depth of the `act` chain.
- A refusal from `ExchangePolicy` records the error code and the client. It never records the
  presented token.
- Streams pick both up with no further change.

### Policy-required step-up

- `sign_in_policies.required_acr`, a string that is null or `urn:masks:acr:mfa`.
- `Login#stepping_up?` is true when either the request or the policy wants `mfa` and the login has not
  used one.
- The manage policy form gets a switch. The policy validation refuses `required_acr` when the policy
  offers no second factor other than backup codes, matching `second_factor_required`.
- `second_factor_required` asks at every sign-in. `required_acr` asks only for the clients the policy
  covers. The docs explain the difference in one table.

### Manage roles

The console is all or nothing today. Buyers want an auditor who can read, a support role that can reset
a factor, and an owner who can change keys.

- Scopes: `masks:manage` stays the owner. Add `masks:manage:read`, `masks:manage:support`, and
  `masks:manage:security`.
- Each manage query and mutation declares the least scope it needs, with one `requires` line in the
  resolver's class. `BaseMutation` refuses when the token lacks it. Queries default to `read`, and
  mutations default to owner, so a forgotten declaration fails closed.
- `support` covers resetting passwords, removing factors, resending invitations, signing out sessions,
  and unblocking devices. `security` covers keys, policies, providers, streams, and adapters. Owner
  covers everything, including granting these scopes.
- An actor cannot grant a scope it lacks. `SetActorScopes` checks this.
- The Svelte app reads the granted scopes from the token and hides actions the viewer cannot take. The
  server check is the real one.
- Tests walk every mutation in the schema and assert it declares a scope, so a new mutation cannot ship
  without one.

### Organizations and roles

- Tables `organizations` (tenant, key, name, settings, archived_at) and `memberships` (tenant,
  organization, actor, role, invited_by, unique on organization and actor), both with row-level
  security like `adapters`.
- Roles are strings an organization defines, with `owner` and `member` built in. An organization has
  at least one owner. Removing the last owner is refused.
- Invitations reuse `Invitation` with an `organization_id` and a role. Accepting one creates the
  membership in the same transaction.
- A client asks for an organization with `organization=<key>` on `/authorize`, or with the scope
  `org:<key>`. The ID token and access token get `org: { key, role }`. A non-member gets
  `access_denied`. A request with no organization and an account in exactly one gets that one. An
  account in several is shown a picker after sign-in.
- `sign_in_policies.organization_id`. `SignInPolicy.for` checks the organization's policy, then the
  client's, then the tenant's.
- `events.organization_id`. Streams gain an optional organization filter, so one customer's log goes to
  that customer's SIEM.
- SCIM provisioning into an organization: a provisioning token can be issued for one organization, and
  accounts it creates become members.
- Manage: `organizations`, `organization`, `createOrganization`, `updateOrganization`,
  `archiveOrganization`, `inviteMember`, `setMemberRole`, `removeMember`, and an Organizations page.
- Events: `organization.created`, `.updated`, `.archived`, `membership.added`, `.role_changed`,
  `.removed`.
- Open question: whether an organization can own clients, so a customer registers its own apps. Leave it
  out of the first cut.

### Home-realm discovery

- Domain proof, shared with custom domains: a `domain_claims` table (tenant, domain, token, verified_at,
  checked_at), with row-level security and a unique index on `domain` across tenants for verified rows.
  A tenant adds a TXT record `_masks-challenge.<domain>` holding the token. A recurring job checks
  unverified claims and rechecks verified ones daily, and a claim whose record disappears for seven days
  is released.
- DNS lookups go through `Resolv::DNS` with a timeout. They are not HTTP, so `Outbound` does not apply,
  and the job never follows a CNAME to a private address because it only reads TXT records.
- `providers.discovers`, a boolean. A provider that discovers and lists `email_domains` that are all
  verified claims receives people whose address is in those domains.
- The identifier step looks up the domain. A match skips the password prompt and starts the provider
  flow with `login_hint`. No match shows the normal form, and the response takes the same time either
  way so the form does not reveal which domains are claimed.
- A policy can require discovery for a domain, so a company's people cannot fall back to a password.
- Events: `domain.claimed`, `domain.verified`, `domain.released`.

### Session policies

- `sign_in_policies.session_lifetime` and `session_idle_timeout`, in seconds, null for the defaults.
- `Session.start!` takes the lifetime from the policy. Each request that touches a session updates
  `last_seen_at` at most once a minute. A session idle past the timeout is ended with
  `session.ended` and reason `idle`.
- Refresh tokens issued under the session expire with it.

### Audit export and retention

- `tenants.event_retention_days`, from 30 to 2555 (seven years), defaulting to 180. `CleanupJob`
  deletes per tenant.
- `exportEvents(from:, to:, action:)` in manage starts an `EventExportJob` that writes NDJSON to
  Active Storage and emails the manager a signed link that expires in a day. Exports are events.
- A large tenant's cleanup deletes in batches so it does not hold a long lock.

### Adaptive risk

- `RiskSignals` scores a sign-in from a new device, a new country (from a configurable GeoIP database
  path, off when absent), a configurable list of address ranges, the time since the last sign-in, and
  failed attempts in the last hour.
- Breached passwords: a k-anonymity range query to a configurable endpoint (the Pwned Passwords API by
  default), through `Outbound`. It sends the first five characters of the SHA-1 and never the password.
  It is off unless the tenant enables it. A breached password at sign-up is refused. At sign-in it adds
  to the score and records `password.breached`.
- `sign_in_policies.risk_rules`: thresholds mapped to `allow`, `step_up`, `notify`, or `deny`.
  `step_up` reuses `stepping_up?`. `notify` sends the security email. `deny` records `login.refused`.
- The score and each signal go in the sign-in event's details, so a stream can alert on them.

### Passwordless email

- Add `email_code` and `email_link` to `FIRST_FACTORS`. They reuse `CodeFactors`, `ConfirmationCode`,
  and `MailedLink`.
- A code used as a first factor never also counts as a second factor, so `amr` is `otp` and `acr` stays
  `pwd` unless a second factor follows.
- Rate limits reuse the existing per-address and per-account limits.
- A link only completes the sign-in in the browser that asked for it. Opened elsewhere, it asks that
  browser to approve, using the existing sign-in approval.

### Custom domains

- Reuses domain proof. `custom_domains` (tenant, host, claim, certificate state, last error).
- Certificates: masks does not terminate TLS today. The first cut documents a proxy (Caddy's on-demand
  TLS) with an `ask` endpoint, `/domains/allowed?domain=`, that answers 200 only for verified hosts.
  Masks-managed ACME comes later if it is needed.
- `Tenant.resolve` looks up a verified custom host before the subdomain. `Tenant#public_origin` prefers
  it. The issuer changes with it, so the switch is a manage action that warns clients will need the new
  issuer, and the old origin keeps answering discovery for 30 days.
- Mail: manage shows the SPF and DKIM records for the domain and checks them before mail is sent from it.

### Shared signals

- Transmitter: a receiver registers an SSF stream with its own bearer token. Masks maps events to CAEP
  and RISC types (`session-revoked`, `credential-change`, `account-disabled`, `account-purged`) and
  sends security event tokens signed with the tenant's key, using the event stream delivery and
  retry code.
- Receiver: `/ssf/events` accepts security event tokens from a provider, verifies them against the
  provider's JWKS, and ends the sessions of the matching connection's account.
- Publish `/.well-known/ssf-configuration`.

### Rich authorization requests

- `authorization_details` on `/authorize`, pushed requests, and token exchange. Each client declares
  the `type` values it accepts and a JSON schema for each.
- The consent screen lists each detail with a label from the client's declaration.
- Granted details go in the access token and in the introspection response.

### Migration

- A `masks:import` runner, not a rake task, reads a file and creates accounts in batches of 500 inside
  `Tenant.switch`, recording one `account.imported` event per batch.
- Formats: Auth0's bulk export (bcrypt hashes, which masks verifies directly), Firebase's `auth:export`
  (modified scrypt with the project's hash parameters), and a generic JSON with `algorithm`, `hash`,
  and `salt`.
- `actors.legacy_password`, encrypted, holding the algorithm and parameters. `Actor.authenticate` tries
  it when `password_digest` is blank, then writes a bcrypt digest and clears it.
- Okta and Cognito do not export hashes. A `legacy_providers` record holds a verification endpoint
  (Okta's authentication API, or a Cognito user migration Lambda URL). On a first sign-in with no
  digest, masks checks the password there through `Outbound`, and on success stores its own digest and
  never asks again. Manage shows how many accounts still depend on it.
- Emails are marked verified only when the export says so.

## Rules for every capability

- Migrations get row-level security, and `structure.sql` is regenerated in the dev container. The diff
  contains only the new table or columns.
- Manage API changes come with the Svelte page, integration tests, and a regenerated reference.
- Anything that calls out from masks goes through `Outbound`, so private addresses are refused.
- Every new action gets an `Event` constant, a label in `events.yml`, and a decision on whether it
  belongs in `GRAVE` or `Notifications::GROUPS`.
- Commits in this repo need a conventional prefix, with a prose subject.
- The docs follow `docs/STYLE.md`. Update the Enterprise page's status when a capability lands.
