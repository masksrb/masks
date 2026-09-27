# Enterprise plan

The public version of this plan is [docs/src/content/docs/guides/enterprise.mdx](docs/src/content/docs/guides/enterprise.mdx).
This file adds the build order, what the code already has, the implementation steps, and the state of
the work.

`PLAN.md` holds an unrelated list of known gaps, so this plan has its own file.

## State

| Capability                      | State        | Commit or next step                                                                                    |
| ------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------ |
| Audit log                       | Built        | `Event`, about 100 actions, 180-day retention                                                          |
| Event streaming                 | Built        | `03b525c`, `bbe2ea1`, guide at `guides/event-streams`                                                  |
| Single sign-on and provisioning | Built        | OIDC, OAuth, SAML in and out, SCIM                                                                     |
| Step-up authentication          | Built        | `a6fd2fe`, and `apps_require_second_factor` on sign-in policies                                        |
| Token exchange                  | Built        | RFC 8693, with `exchange.granted` and `exchange.refused` events. RFC 9396 is item 11                   |
| Manage roles                    | Built        | `ManageRoles`, a declared level on every mutation, and the limits in the security guide                |
| Organizations and roles         | Partly built | Steps 1 and 2 of 4: the `org` claim and picker, then organization policies, providers, and directories |
| Home-realm discovery            | Not started  |                                                                                                        |
| Session policies                | Built        | `sign_in_policies.session_lifetime` and `session_idle_timeout`                                         |
| Audit export and retention      | Not started  |                                                                                                        |
| Adaptive risk                   | Not started  |                                                                                                        |
| Passwordless email              | Not started  |                                                                                                        |
| Custom domains                  | Not started  |                                                                                                        |
| Shared signals                  | Not started  |                                                                                                        |
| Migration                       | Not started  |                                                                                                        |

## What the code already has

Checked against the code on 2026-09-27. Each planned item starts from these.

- **Token exchange.** `Exchange` implements RFC 8693: access and ID tokens as the subject, actor tokens,
  a nested `act` chain, and upstream tokens released through `Delegation`. `Exchange#perform!` records
  each grant and refusal.
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

| #   | Capability                                        | Size | Depends on    | Why here                                                                  |
| --- | ------------------------------------------------- | ---- | ------------- | ------------------------------------------------------------------------- |
| 1   | Token exchange events and policy-required step-up | S    |               | Done                                                                      |
| 2   | Manage roles                                      | M    |               | Done                                                                      |
| 3   | Organizations and roles                           | L    | 2             | Everything per-customer builds on it                                      |
| 4   | Home-realm discovery                              | M    | Domain proof  | Makes SSO usable without a per-customer sign-in link                      |
| 5   | Session policies                                  | S    |               | Done                                                                      |
| 6   | Audit export and retention                        | S    |               | SOC 2 evidence and regulated retention periods                            |
| 7   | Adaptive risk                                     | M    | 1             | Reuses step-up                                                            |
| 8   | Passwordless email                                | M    |               | Consumer and low-friction B2B markets                                     |
| 9   | Custom domains                                    | L    | Domain proof  | Needs certificates and a second tenant lookup                             |
| 10  | Shared signals                                    | M    | Event streams | Reuses delivery and signing                                               |
| 11  | Rich authorization requests                       | M    | 1             | Finishes token exchange                                                   |
| 12  | Migration                                         | L    |               | Adoption, and Okta and Cognito need a live check against the old provider |

Domain proof is shared by 4 and 9, so it is built once with 4.

Each capability is its own commit or series of commits, with tests, docs, a regenerated reference
(`./dev reference`), and a `structure.sql` diff that contains only its own tables.

## Implementation

### Token exchange events (done)

- `Exchange#perform!` validates, issues or releases, and records `exchange.granted` with the scopes,
  audience, token types, the acting party, and the depth of the `act` chain. A `Policy::Denied`
  records `exchange.refused` with the error and description, then re-raises. The presented token is
  never recorded.
- `exchange.refused` is in `Event::GRAVE`. Delegation events gained the labels they were missing.

### Policy-required step-up (done)

- `sign_in_policies.apps_require_second_factor`, a boolean. A plain switch fits better than an `acr`
  string while masks has only two levels.
- `Login#stepping_up?` is true when the request or the policy wants a second factor, the login has an
  authorization request, and neither the login nor the session has used one. Signing in to masks
  itself, with no request, is not stepped up.
- Validation refuses it when the policy offers only backup codes or trusted devices, matching
  `second_factor_required`.
- `second_factor_required` makes every account hold a second factor, and a session that skipped it
  still reaches apps. `apps_require_second_factor` asks for it again at each app sign-in that has not
  used one.

### Manage roles (done)

- `ManageRoles` names four scopes and four levels. `read` is any of them, `support` is
  `masks:manage:support` or owner, `security` is `masks:manage:security` or owner, and `owner` is
  `masks:manage`.
- `ManageEndpoint` accepts a token that carries any of them, and the roles in force are the ones both
  the token and the actor hold, so taking a role away ends it on the next request.
- `BaseMutation.requires` declares a level, and `authorized?` refuses with the scopes the mutation
  needs. The default is owner. A test walks the schema and fails on any mutation that did not declare
  one. Today: 24 support, 37 security, 3 owner (`setActorScopes`, `updateTenant`, `deleteActor`).
- Below owner: `actor!` and the lookups behind sessions, tokens, consents, connections, and
  delegations refuse another manager's records. `device!` refuses a device another manager has a live
  session on. `granting!` refuses handing out a manage scope to a person or a client. `client!`
  refuses a client that can carry a manage scope, which keeps the console's redirect in an owner's
  hands.
- Handshakes: only an owner connects the manage console. Another manager joins the connected console
  from a new browser, and only when the handshake matches it exactly.
- The console asks for all four scopes and gets the ones the person holds. `manageLevels` tells it
  which, and it shows a line saying what the viewer can do. Hiding each action the viewer cannot take
  is a follow-up. The server check is the real one.
- Approval requests now email support managers as well as owners.

### Organizations and roles

Decided 2026-09-27: an account may belong to no organization, and organizations do not own clients in
the first cut. Apps stay tenant-wide and ask for an organization.

**Step 1 (done).**

- `organizations` (key, uuid, name, extra `roles`, archived) and `memberships` (organization, actor,
  role, invited_by), both under row-level security. `tokens.organization_id` carries the choice from
  the code to every access and refresh token after it.
- `owner` and `member` are built in. `Membership` refuses to demote or remove the last owner, except
  when the actor or organization itself is deleted.
- The `organization` scope is standard. `LoginStates::OrganizationChoice` runs before consent when a
  request's granted scopes include it: a named `organization` must be one of the person's, one
  membership is taken without asking, several prompt `choose-organization`, and none is refused with
  `access_denied`. The choice is tied to the request's rid.
- `org` is `{ id, key, name, role }` on access and ID tokens, read from the membership each time a
  token is issued. The token endpoint refuses a code or refresh whose account has left the
  organization. Archiving an organization or removing a member revokes its live tokens.
- Manage: `organizations`, `organization`, `create`/`update`/`archive`/`restoreOrganization`
  (security), and `addMember`, `setMemberRole`, `removeMember` (support). `addMember` by email invites
  an account that does not exist. Organizations has its own page in the main nav, and actors list
  their memberships.

**Step 2 (done).**

- `organizations.sign_in_policy_id`. `SignInPolicy.for` checks the organization, then the client, then
  the tenant. `Login#organization` is the chosen organization, or the one the request names, and
  `Login#policy` is memoized per organization so a choice mid-flow switches it.
- `OrganizationChoice` moved to right after the first factor, so a chosen organization's policy decides
  the second factor, enrolment, session limits, and step-up. The first factor follows the request's
  named organization, or the app's policy when none is named.
- `providers.organization_id`, `role_claim` (default `groups`), `role_map`, and `unmapped_role`
  (default `member`; `default_role` collides with Active Record). An organization's provider is offered
  only when `Login#organization` is that organization. `SingleSignOn#link` sets the membership and
  role on every sign-in. A sign-in that claims an existing account by proving its password links the
  connection without a membership until the next sign-in through the provider.
- `issueProvisioningToken(organization:)` stores it on `tokens.organization_id`, and SCIM reads it from
  the provisioner. Such a token lists and reads only members, creates accounts that join as `member`,
  changes only members of no other organization, and turns `DELETE` into leaving the organization.
  It never suspends or deletes the account.
- Manage: `updateOrganization(signInPolicy:)`, `setProviderOrganization`, and the organization picker
  on Provisioning. The organization page sets the policy and hands providers over with a group map.

**Step 3.** `events.organization_id`, and an optional organization filter on event streams.

**Step 4.** A self-service admin view for an organization's owners, without any `masks:manage` scope.

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

### Session policies (done)

- `sign_in_policies.session_lifetime` and `session_idle_timeout`, in seconds, from 5 minutes to 400
  days, idle shorter than lifetime. Null keeps 14 days and no idle timeout.
- `sessions.last_seen_at`, `idle_timeout`, and `bounded`, copied from the policy the login ran under.
  `Session.resume` touches `last_seen_at` at most once a minute and ends an idle session with
  `session.expired`, which also announces a backchannel logout. `Session.live` leaves idle sessions
  out.
- A stricter app policy applies to a session started under another one: `Login#stale?` is true when
  the session is older than the app's lifetime or sat idle longer than its timeout, so the app asks for
  the first factor again. The idle check is remembered in the login so the follow-up requests do not
  forget it.
- A refresh token whose session is bounded is refused once the session is no longer live, including
  after signing out. Unbounded sessions leave refresh tokens alone, so `offline_access` keeps working
  as before.
- Manage's policy form has a **Sessions** row with preset lifetimes and idle timeouts.

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
