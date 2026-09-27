# Enterprise plan

The public version of this plan is [docs/src/content/docs/guides/enterprise.mdx](docs/src/content/docs/guides/enterprise.mdx).
This file adds the build order, the implementation steps, and the state of the work.

`PLAN.md` holds an unrelated list of known gaps, so this plan has its own file.

## State

| Capability | State | Commit or blocker |
| --- | --- | --- |
| Audit log | Built | `Event`, about 100 actions, 180-day retention |
| Event streaming | Built | `03b525c` engine, API, and tests; `Streams` tab in manage; guide at `guides/event-streams` |
| Single sign-on and provisioning | Built | OIDC, OAuth, SAML in and out, SCIM |
| Step-up authentication | Built | `acr_values` and the `claims` `acr` request a second factor; `test/integration/step_up_test.rb` |
| Organizations and roles | Not started | |
| Home-realm discovery | Not started | |
| Adaptive risk | Not started | |
| Custom domains | Not started | |
| Shared signals | Not started | |
| Token exchange | Not started | |
| Migration | Not started | |

## Order

1. Organizations and roles. Everything per-customer builds on it.
2. Home-realm discovery. It needs domain proof, which custom domains reuse.
3. Adaptive risk.
4. Custom domains.
5. Shared signals. It reuses event stream delivery.
6. Token exchange.
7. Migration.

Each capability is its own commit or series of commits, with tests, docs, a regenerated reference
(`./dev reference`), and a `structure.sql` diff that contains only its own tables.

## Implementation

### Organizations and roles

- Tables `organizations` (tenant, key, name, archived_at) and `memberships` (organization, actor,
  role, unique on the pair), both with row-level security like `adapters`.
- Roles are strings a tenant defines per organization, with `owner` and `member` built in.
- Invitations reuse `Invitation` with an `organization_id`.
- A token request names an organization with an `organization` parameter. The token gets an `org`
  claim with the key and the member's role. A non-member is refused with `access_denied`.
- Sign-in policies gain an optional `organization_id`, so `SignInPolicy.for` picks the organization's
  policy first.
- Events gain an `organization_id` column, and streams gain an optional organization filter.
- Manage: `organizations`, `createOrganization`, `addMember`, `setMemberRole`, `removeMember`, and an
  Organizations tab.

### Home-realm discovery

- `provider_domains.rb` exists. Add `domains` claims that a tenant proves with a DNS TXT record
  (`_masks-challenge.<domain>`), stored with a token and a `verified_at`.
- The identifier step looks up the address's domain. A verified claim starts that provider's flow. No
  claim shows the normal form.
- A domain is claimed by one tenant at a time. Releasing it is an event.

### Adaptive risk

- `RiskSignals` scores a sign-in from device newness, IP reputation (a configurable list), distance
  in time from the last sign-in, and a breached-password check by k-anonymity range query.
- `SignInPolicy` gains `risk_rules`: a score threshold mapped to `allow`, `step_up`, or `deny`.
- `step_up` reuses `stepping_up?`. `deny` records `login.refused`.
- The score and the decision go on the sign-in event. The breach check never sends the password or its
  full hash, and it is off unless the tenant enables it.

### Custom domains

- A `domains` table (tenant, host, verified_at, certificate state). A tenant proves a host with a DNS
  record, then masks requests a certificate through ACME and renews it.
- `Tenant#public_origin` prefers the verified domain. Issuer, links, emails, and cookies follow it.
- Mail from the domain needs the tenant's SPF and DKIM records, which manage shows and checks.
- Requests for an unverified host are refused before tenant resolution.

### Shared signals

- Transmitter: a receiver registers a stream, and masks maps events to CAEP and RISC event types
  (`session-revoked`, `credential-change`, `account-disabled`), sending signed security event tokens
  with the event stream delivery and retry code.
- Receiver: an endpoint accepts security event tokens from a provider, verifies them against the
  provider's keys, and ends the matching sessions.
- Publish `/.well-known/ssf-configuration`.

### Token exchange

- `grant_type=urn:ietf:params:oauth:grant-type:token-exchange` at the token endpoint, with
  `subject_token`, `resource`, `scope`, and an optional `actor_token`.
- The result is limited to the intersection of the subject token, the client's delegation, and the
  request. The token carries `act` for the actor.
- `authorization_details` (RFC 9396) is validated against a per-client schema.
- Each exchange is an `exchange.granted` or `exchange.refused` event.

### Migration

- A `masks:import` runner reads Auth0, Okta, Cognito, and Firebase exports and creates accounts in
  one transaction per batch.
- Password hashes are kept in their source format in a `legacy_hash` column and verified with that
  algorithm. The first successful sign-in rewrites them with the masks hash.
- Emails are marked verified only when the export says so. Every import is an event.

## Rules for every capability

- Migrations get row-level security, and `structure.sql` is regenerated in the dev container. The diff
  contains only the new table or columns.
- Manage API changes come with the Svelte page, integration tests, and a regenerated reference.
- Anything that calls out from masks goes through `Outbound`, so private addresses are refused.
- Commits in this repo need a conventional prefix, with a prose subject.
- The docs follow `docs/STYLE.md`. Update the Enterprise page's status when a capability lands.
