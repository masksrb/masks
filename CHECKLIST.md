# masks — checklist

What is built, what is inherited but not yet ported, and what is still ahead.

**Read at `f8b8e25`, plus the first-run work in the working tree.** The container, conformance,
login, schema and suite work that the last read found loose is committed, in nine chunks. Everything
marked done has been **run**, not merely written. Where a claim has
only been read rather than executed, it says so — an unexecuted checked box is the shape most bugs
here would take. §6 now carries one that was checked and false for exactly that reason.

**Both suites are green as this is written.** masks' own: 184 runs, 485 assertions, 0 failures.
The OpenID Foundation's: **both certification plans complete with 0 failures and no unexpected
warnings** — 2178 conditions across 39 modules on the basic plan, 35 on config. That is what §11
now records, read from a finished run rather than one in flight. Two loose things are in the tree:
the conformance work (§2 §4 §11) and first run (§1 §2, `plans/020`).

**masks ships four deliverables, not three.** The server, the Ruby client gem, the Rails engine, and
`@masks/client` for the browser. §6 §7 §8 are the three a consumer touches, and between them they
are the least exercised code in the repo.

|         |                 |                                                     |
| ------- | --------------- | --------------------------------------------------- |
| `- [x]` | **done**        | built and exercised                                 |
| `◐`     | **partial**     | exists but incomplete                               |
| ` `     | **to build**    | nothing yet                                         |
| `↧`     | **inheritable** | written in a previous masks; port rather than write |

The end-to-end run covers: discovery, JWKS, dynamic registration, RFC 7592 read-back, authorize with
PKCE and a resource indicator, sign-in, TOTP, consent, code exchange, userinfo, refresh rotation,
token exchange, cascading revocation, and key rotation — plus six rejections: replayed code, wrong
registration token, cross-tenant client, cross-tenant token, widened scope, widened audience.

---

## 1. Tenancy and keys

- [x] **Tenant model, with a stable `uuid` distinct from `subdomain`** — a subdomain is a routing
      fact someone will rename; a uuid is identity. Downstream apps key on the uuid.
- [x] **masks is the source of truth for tenants** — the identity travels in a `tenant` claim on
      every access token and id token, and in the discovery document. A consumer reads a claim
      rather than calling back, which is also why it never forwards a caller's token upstream.
- [x] **Row-level security** — `FORCE`, a non-superuser application role, `TenantScoped` over the
      top. Written fresh; grepping the prior masks for "tenant" returns nothing.
- [x] **The schema is dumped as SQL, because `schema.rb` silently discarded every policy.** The
      first two RLS tests written failed, and the reason was not the tests: `schema.rb` cannot
      represent `CREATE POLICY` or `FORCE ROW LEVEL SECURITY`, and `db:prepare` builds a fresh
      database from the schema rather than from migrations. **The container had zero policies and
      zero forced tables** — the isolation §1 claims was real only in databases built by running
      migrations in order, which the dev machine was and no fresh deploy would have been. The
      cross-tenant refusals verified earlier still passed, because `TenantScoped`'s default scope
      caught them in Ruby; the database layer meant to catch a _bypassed_ scope was not there at
      all. Now `schema_format = :sql`, `db/structure.sql` carries all twelve statements, and a
      dropped-and-recreated container database comes back with all six tables policed and forced.
      The cost is a `pg_dump` matching the server, which refuses outright when it is older: `bin/setup`
      checks for one before doing anything and says what to do about it, `PG_BIN_PATH` in
      `server/.env` prepends a specific toolchain, and the `Brewfile` pins what to install.
- [x] **Three tests now assert the policies exist** — that every model including `TenantScoped` has
      a `tenant_isolation` policy, that every such table is `FORCE`d, and that the application role
      is neither superuser nor `BYPASSRLS`. Derived from the models, so a new scoped model without a
      policy fails. This is the check whose absence hid the bug above.
- [x] **`Tenant.switch` restores the outer tenant on the way out** — nesting does not blind the
      caller to its own rows.
- [x] **A tenant is declared or claimed, and until now was neither** — every tenant came from
      `db/seeds.rb`, so a fresh deployment served 404 at every hostname until someone edited seeds.
      `MASKS_TENANTS` declares them and `masks:tenants` ensures them, which is what the container
      entrypoint now runs beside `db:prepare`; unset, the first request to an unresolvable host
      claims that subdomain. **Claiming is one-shot: it is refused the moment any tenant exists**,
      so it cannot be used to mint tenants at a hostname wildcard, and a claimed tenant is worth
      nothing until §2's setup prompt is answered. Driven over HTTP: an empty deployment claims and
      then asks to be set up, a second hostname is 404, a declared list turns claiming off, and a
      subdomain the format rejects claims nothing.
- [x] **Per-tenant signing keys, from migration #2** — RSA per tenant, generated on create, `kid`
      published through that tenant's JWKS only. The isolation layer that fails _loudly_: acme
      answers a valid jons token with "could not find public key for kid".
- [x] **Key rotation with an overlap window** — `SigningKey.rotate!`. Verified: JWKS publishes both
      during the overlap, outgoing-key tokens still verify, new tokens carry the new `kid`.
- [ ] **Rotation on a schedule** — `rotate!` exists and nothing calls it. A key that is never rotated
      is a key whose rotation path is untested in production.
- [ ] **Per-tenant encryption keys** — credentials are encrypted with one application-wide key set.

## 2. The OIDC flow

- [x] **Authorization code + PKCE** — S256 only; `plain` is not supported. Mandatory for public
      clients, accepted from all.
- [x] **Codes are single-use and bound** — to their client and their `redirect_uri`, and they carry
      the audience they were authorized for. Consumed on use whether or not the verifier matches.
      **This line was false until §11's tests were written.** `consume!` ran _after_ the PKCE check
      and behind an early return, so a wrong `code_verifier` left the code live and a second attempt
      with the right one succeeded — the interception the check exists to catch got a retry. The
      code is now burned once the client and `redirect_uri` bind, before the verifier is examined,
      and not before: burning on a client mismatch would let any registered client invalidate any
      code. The claim was three months old and read as true every time.
- [x] **Refresh with rotation** — the presented token is consumed and a child minted recording its
      parent. A replayed refresh fails.
- [x] **Audience-restricted tokens — RFC 8707** — the `resource` becomes the token's `aud`. Repeated
      values are parsed off the raw query and body, because Rails keeps only the last.
- [x] **Per-tenant discovery** — `/.well-known/openid-configuration` and
      `/.well-known/oauth-authorization-server`.
- [x] **The authorization request may arrive by POST** — OIDC Core 3.1.2.1 requires both verbs and
      the route served only `GET`, which is a route that is not there rather than a flow that went
      wrong. Forgery protection is skipped for it deliberately: a `POST /authorize` is a cross-site
      form post from the client and carries no session of ours to forge against. §2's repeated-value
      parsing had to grow the same way — `resource` can now appear twice in a body as well as twice
      in a query, and Rails keeps only the last of either.
- [x] **A request object is refused rather than ignored, and discovery says so** — masks read the
      plain query and took no notice of `request` or `request_uri`, so the `state` and `nonce` a
      client had **signed** were dropped and the unsigned ones won. _Silently preferring unsigned
      input over signed input is the wrong direction to fail in_, and it presented as two modules
      failing `CheckStateInAuthorizationResponse` and `ValidateIdTokenNonce` rather than as anything
      masks logged. Now `request_not_supported` / `request_uri_not_supported`, the codes OIDC Core 6
      defines for an issuer that does not support them, raised **after** the `redirect_uri` is
      verified so the refusal reaches the client rather than the browser — and
      `request_parameter_supported` and `request_uri_parameter_supported` are declared `false` in
      discovery, so a client learns it from metadata instead of from an error.
- [x] **The id token carries identity and nothing a scope asked for** — OIDC Core 5.4: in a flow
      that issues an access token, the claims a scope requests come from userinfo. masks put them
      in both, which hands a name and an email address to everything that reads the token instead
      of to what presents one. The id token is now `sub`, `acr`, `auth_time`, `nonce`, the two
      hashes and `tenant`; §6's `Session#identity` merges userinfo *under* the verified id-token
      claims, so a consumer's identity is unchanged and an issuer that still sends the claims in
      the token keeps working.
- [x] **The `claims` request parameter, for userinfo** — OIDC Core 5.5, a client naming a claim
      rather than asking for the whole scope that contains it. Parsed at authorize, carried on the
      authorization code and then the access token, and released at userinfo. Essential and
      voluntary are treated alike: masks releases what it holds, and refusing a voluntary request
      only teaches the client to ask for the broader scope instead.
- [x] **`acr`, and two values masks can actually assert** — `urn:masks:acr:pwd` and
      `urn:masks:acr:mfa`, advertised in `acr_values_supported` so a client can ask with
      `acr_values` and check what it got. The value follows whether the actor holds a second
      factor, which is the same fact as whether one was used: the login machine will not settle
      with a factor pending.
- [x] **`profile` releases the standard claim set** — thirteen claims, not two. `actors` carries
      `given_name`, `family_name`, `middle_name`, `profile_url`, `picture_url`, `website_url`,
      `gender`, `birthdate`, `zoneinfo` and `locale` alongside the name and nickname it had, and
      `updated_at` comes from the row. All nullable and all `compact`ed away when unset, so an
      actor releases what it has and omits the rest rather than answering `null`. **There is no UI
      for any of it** — §3's missing admin surface now has ten more fields waiting on it.
- [x] **A refusal with nowhere safe to send it is rendered for a person** — when the `redirect_uri`
      is missing or unregistered there is no client to answer, and masks answered a JSON body to
      what is always a browser. §3's exact-match rule was doing its job and the person driving saw
      a blob of JSON; the conformance runner saw a hung browser. Now an HTML page naming the error
      code and what it means, with the JSON kept for every non-HTML caller.
- [x] **userinfo** — scope-gated: `profile` releases the name, `email` the address, neither without.
- [x] **`iss` on the authorization response** — so a client with several issuers knows which answered.
- [x] **The authorize and token endpoints run on rack-oauth2** — and the request is validated from a
      params hash rather than the live env, because this request is not happening now: it stops for
      sign-in, stops again for consent, and resumes out of the session later. The same hash
      `to_session` round-trips, so a resumed authorization is checked by exactly the same code as a
      fresh one, and the throw/catch that used to break out of the handler is gone. Token exchange
      is a gem extension rather than a branch. `prompt=none` refuses with `interaction_required`,
      which `openid_connect` defines, rather than a hand-written `bad_request`.
- [x] **`auth_time` is when the person signed in, and `max_age` is enforced against it** — it was
      set to the moment the id token was built, which made it a copy of `iat` and said nothing:
      sign in at nine, reuse consent at eleven, and the old claim swore you had just authenticated.
      That is also why `max_age` could not be honoured. The session's `authenticated_at` now travels
      with the authorization code, so the claim survives the round trip through login and consent.
      `max_age` is checked before consent alongside `prompt=login`, and refuses with
      `interaction_required` when the client also said `prompt=none` — asking not to be interrupted
      and demanding a fresh authentication at once cannot both be satisfied.
      **The ceiling that does not force a re-authentication works and the one that does hangs**:
      `oidcc-max-age-10000` passes, `oidcc-max-age-1` never completes. The claim above is true of
      the check and false of what happens next, which is the same defect `prompt=login` has. §11.
- [x] **`at_hash` binds the id token to the access token it was issued with** — the left half of the
      SHA-256, so a client can confirm the two were issued together rather than paired by whoever
      delivered them. Optional for the code flow, required the moment an id token travels the front
      channel, so it may as well be there now. `c_hash` is wired for when it does.
- [x] **userinfo accepts a bearer token the way RFC 6750 says it may arrive** — header _or_ form
      parameter, and `invalid_request` when a caller sends both, which is the case the spec is
      careful about and the one a hand-written extraction never thinks of. `Resource::Bearer`
      carries the `WWW-Authenticate` shapes with it, `insufficient_scope` as a 403 naming the scope
      it wanted rather than a bare denial. It is middleware by design and is called from inside the
      action anyway, because mounted as middleware it would run before `Tenant.resolve` and verify
      tokens against whichever issuer answered first.
- [x] **Custom scopes, and a ceiling at each end** — a consumer's own scopes (`catalog:read`,
      `admin`) travel in the `scope` claim on the access token and need no registration here;
      `scopes_supported` in discovery advertises only the four masks defines, because a resource
      server advertises its own in RFC 9728 metadata. Nothing is checked against a global allowlist.
- [x] **A scope is bounded twice, and the two bounds deliberately differ** — the client's
      registration is a static contract, so requesting outside it is refused whole with
      `invalid_scope` rather than narrowed. The actor's grant is a fact about a person, so a scope
      they lack is **narrowed away silently**: a non-admin signing in to a client registered for
      `admin` gets a token without it, rather than being unable to sign in at all. Getting these the
      same way round breaks one case or the other.
- [x] **The actor bound now exists at all** — `actors.scopes` and `Actor#scope_list` were built and
      **nothing called them**; `granted_scopes` was the client's registration alone. Since
      registration is open and unauthenticated by design, that made any custom scope self-serve:
      register a client naming `admin`, sign in, consent, and the token carries it. **A scope says
      what a client may do on behalf of an actor, never who that actor is** — so authority has to be
      bounded by something masks holds about the person. Seven tests drive it through the real flow.
- [x] **A blank `actors.scopes` means the four masks defines, not none and not everything** — an
      actor's identity scopes are their own; app authority is not. `none` would have stopped every
      existing actor refreshing, and `everything` would have restored the hole above.
- [x] **Remembered consent** — per actor and client, unioning scopes and audiences.
- [x] ◐ **`prompt`** — `consent` re-asks and `none` refuses to interact; both pass the conformance
      suite. **`login` does not work**: it interrupts and the browser never gets back, and
      `oidcc-prompt-login` hangs on it for 241 seconds without a verdict. See §11.
- [x] **Sign-in is a progressively enhanced prompt machine** — the server owns an ordered list of
      `LoginState`s and answers with the next `prompt`. Every prompt exists twice: as an ERB partial
      whose `form_with` posts an `event` to `login_path` and gets a redirect back, and as a Svelte
      component posting the same events as JSON. `logins/show` renders the partial; `login.js`
      replaces it only if the bundle runs. `LoginsController#update` answers both formats from one
      code path. Driven end to end in dev _and_ in the container: identify → first-factor →
      second-factor → settled, with a wrong password and a wrong code each warning without
      advancing. **The earlier "sign-in now requires JavaScript" was reversed by building the
      partials** — which is the property §11's conformance harness wanted back. Read, not yet
      driven with JS off: nothing has executed the no-JS path deliberately, and HtmlUnit completing
      the flow does not prove it, since HtmlUnit runs the bundle.
- [x] **Adding a factor is adding two files** — a `LoginState` and a prompt component. The order of
      `Login::STATES` is the flow; nothing else encodes it.
- [x] **First run is a state at the head of that flow, not a wizard beside it** — `plans/020`.
      **masks had no signup at all**: no `Actor.create` outside seeds and the console, no setup
      route, so the documented way to install this was to edit `db/seeds.rb` and redeploy.
      `LoginStates::Setup` prompts while the tenant has no actors, creates the owner with the four
      scopes masks defines, and hands the same login the first factor — so setup _is_ the sign-in
      rather than a detour before one. `enabled?` is the whole guard, and it goes false the moment
      an actor exists, which is why the prompt cannot reappear. It cost two files and one line in
      `STATES`, which is the claim above holding for something that is not a factor: **onboarding
      steps are high-up-the-chain policies, and the ordered list is where they belong.** Driven at
      both levels — fifteen model tests, and thirteen over HTTP including the no-JS form path, one
      tenant's setup not touching another's, and the created owner completing a full OIDC flow.
- [x] **A state can contribute to what the browser is told** — `LoginState#as_json`, merged for
      enabled states only, so `setup.token` is published while setup is possible and not after.
      Without it the prompt could not know whether to ask for a token, and the alternative was
      leaking that a setup token is configured on every login response forever.
- [x] **`MASKS_SETUP_TOKEN` is optional, and that is a deployment decision** — set, and first run
      demands it; unset, and first run is open until an actor exists. The permissive default is
      deliberate: a `compose up` on a laptop should not have to go fishing in a log, and the host
      that needs the guard already has an env file. **The risk, not designed away: unset on a
      reachable host, the window between boot and first visit is a land grab.** The token is
      compared with `secure_compare`, a missing one is refused rather than treated as blank, and
      `setup` is rate-limited as a verifying event, so guessing it is bounded like a password.
- [ ] **Nothing has driven the setup prompt in a browser** — the ERB partial is exercised by the
      form-encoded test and the Svelte component builds, but no browser has run it. The same
      caveat §2 carries for the no-JS path, in the other direction.
- [x] **The identifier step never looks the actor up** — so §5's anti-enumeration property survives
      the split into two steps. Measured through the machine: 282.4 / 283.6 / 283.1 ms for
      real-wrong-password, no-such-account, and correct, with identical prompt and warning.
- [x] **Password auth and a TOTP second factor** — driven end to end: a correct password alone does
      not sign you in while a factor is pending, a wrong code is refused, a valid one completes.
- [ ] **Backup codes** — a second factor with no recovery path locks people out.
- [ ] **`end_session_endpoint` is advertised but only clears the local session** — no RP-initiated
      logout, no `id_token_hint`, no `post_logout_redirect_uri`.

## 3. Clients and registration

- [x] **Dynamic client registration — RFC 7591** — an AI client adding a connector registers with no
      prior arrangement. Without it that flow cannot be set up at all, which is why it is v1.
- [x] **Registration management — RFC 7592** — read, update and delete against a registration access
      token. A wrong token, or the right token against another tenant, is 401.
- [x] **Public clients** — `token_endpoint_auth_method: none`, PKCE then mandatory.
- [x] **A registration naming no scopes gets everything masks defines, `offline_access` included** —
      it used to get three, and a client that cannot refresh has to push the person back through
      sign-in to keep working, which is a worse outcome than the token it was denied. What a client
      may ask for _beyond_ the four is this section's ceiling, which is a different question and
      still unbuilt.
- [x] **Client authentication** — `client_secret_basic` and `client_secret_post`, bcrypt digests.
- [x] **Redirect URIs validated at registration** — absolute, no fragment, https unless loopback.
      `*.localhost` counts as loopback everywhere, per the URL spec; plain http is additionally
      allowed on any host in development and test, because `.test` genuinely is not loopback and the
      documented local setup uses it.
- [x] **Exact-match redirect URIs at authorize** — no prefix or wildcard matching.
- [ ] **There is no such thing as a configured client, and the schema pretends otherwise.**
      `Client` is tenant-scoped and carries `redirect_uris`, `scopes`, `grant_types`, `resources`,
      an auth method, `dynamic` and `archived_at` — the shape of "a tenant has many clients with
      different configs". But **`Client.register!` is the only constructor**, it hardcodes
      `dynamic: true`, and nothing anywhere reads `dynamic`. Nothing seeds a client. So every client
      that can exist is an anonymous self-registration, and the column that would distinguish a
      first-party app from a stranger's connector is decoration.
- [ ] **Which makes §2's client bound decorative.** §2 says the client's registration is a static
      contract, so requesting outside it is refused whole rather than narrowed. That is only true of
      a client somebody configured. `scope` is in `RegistrationsController::METADATA` and `create`
      is unauthenticated — **a dynamic client writes its own contract.** Two of the three ceilings
      are therefore one: the actor bound is all that stands between a stranger's registration and a
      consumer's `admin`. Configured clients are what make the client bound mean anything.
- [ ] **Approved clients, created by a human rather than seeded** — `plans/020` answers this
      differently from the way it was filed, and the filed version should be read as rejected. A
      seeded configured client assumes a deployer holding a secret for both halves at once; a
      self-hosted install is one person, one browser, and two servers that have never met. So:
      an **initial access token** — RFC 7591 §3.1, which masks does not implement — minted by an
      owner in the approval screen, carried one-time through the browser, and redeemed by the
      consumer at `/register` server to server. The client that comes back is `dynamic: false`,
      records who approved it, and **is the first thing that ever reads that column.**
      What survives from the seeded version: `client_id` is unique per `tenant_id`, so the same
      `client_id` string in every tenant resolves to a different row.
      Not built. §2's setup prompt is the half of `plans/020` that is.
- [ ] **`required_scopes` and `allowed_scopes`, replacing `scopes`** — required are granted whether
      or not asked for; allowed are grantable on request; the ceiling is their union. Ported from
      the previous masks, which had `require_scopes=` / `allow_scopes=` / `remove_scopes=` over
      exactly this pair.
- [ ] **A ceiling on what a dynamic client may request**, declared per tenant. Registration stays
      open, and trims to that set rather than refusing — RFC 7591 lets the server replace what was
      asked for and return what was granted, and a connector that asked for too much should still
      work with less. Note the asymmetry, which is deliberate: **registration trims, authorize
      refuses, the actor narrows.** Each behaves the way its own failure should read.
- [ ] **The default on that ceiling is the trap.** Discovered by building it and watching the suite
      go red: default it to the four scopes masks defines and **every connector flow breaks**, since
      masks does not know what a consumer's scopes are and never should. It has to default
      permissive, or be declared per tenant before a consumer's scopes exist.
- [ ] **Consent skipped for a trusted configured client** — a tenant approving a scope grant to
      their own first-party app is theatre, and the screen trains people to click through. Only a
      configured client may be trusted; a dynamic one is always asked.
- [ ] **Client secret rotation** — secrets are issued once and never expire. `secret_expires_at`
      exists on the column and nothing sets it.
- [ ] **Client ID Metadata Documents** — the alternative to DCR that some clients prefer. DCR covers
      the need today; CIMD is worth knowing whether Claude sends it.
- [ ] **Open registration is unauthenticated** — deliberately, since connectors need it, but there is
      no software statement, no allowlist, and nothing but a rate limit bounding it. §2's actor
      bound is what keeps this from being a way to mint authority; it is not a reason to stop
      wanting one of the three.
- [ ] ◐ **Granting an actor a scope has almost no interface** — §2's setup prompt is the first thing
      that ever wrote `actors.scopes` outside seeds and the console, and it writes exactly the four
      masks defines. Every _custom_ scope is still console-only, which is what strands the first
      consumer: an actor signs in successfully and then every one of that consumer's fields refuses.
      `plans/020` puts the grant in the approval screen, where the scopes being asked for are on
      screen anyway. An admin UI is still the missing half.
- [ ] **A custom scope has no consent-screen description** — `Scopes::DESCRIBED` covers the four
      masks defines, so a consumer's scope shows as a bare string. The name is the only thing the
      person approving it gets to read, which makes `admin` legible and `x:w` not. Either a
      registered client declares descriptions, or the resource server's RFC 9728 metadata does.

## 4. Exchange and revocation

- [x] **Token exchange — RFC 8693** — narrows in three directions at once: scope must be a subset,
      audience must be a subset, and the lifetime ceiling is the subject's expiry whatever was asked
      for. Each is refused rather than silently trimmed.
- [x] **The `act` claim, chained** — an exchanged token names the client that exchanged it and nests
      on each further exchange, so a token carries its own provenance.
- [x] **Revocation — RFC 7009 — that cascades** — exchanged tokens record a parent, so revoking a
      root revokes its children and theirs. Verified root/child/grandchild 200 → 401 in one call.
- [x] **A revoked token cannot be exchanged.**
- [x] **Replaying a code revokes what the code already bought** — §2's code-consumption fix burned
      the code and stopped there, which left the interceptor holding the access token the code was
      only ever a means to. OIDC Core 3.1.3.2 says the tokens issued from a replayed code should go
      with it. An access token now records the code as its parent, so the cascade §4 already had
      does the work; `Token.spent` looks the code up _outside_ the `live` scope, because a replay is
      only visible on a record `redeem` has already refused.
- [ ] ◐ **Revocation is invisible to offline verification** — immediate against masks, and unseen by
      a resource server doing JWT-only validation until expiry. The mitigation is short exchanged
      lifetimes, not long tokens you hope to recall. A resource server should not cache validation.
- [ ] **Token introspection — RFC 7662** — the endpoint that would let a resource server ask rather
      than assume. The honest answer to the item above.
- [ ] **Actor tokens** — `actor_token` is accepted by the RFC for delegation, not impersonation. Only
      impersonation-with-narrowing is implemented.

## 5. Hardening

- [x] **The cache is real in every environment** — `config/cache.yml` named the cache database only
      under `production`, so development and test fell back to the primary and `Rails.cache` raised
      on first write; test was a `:null_store` on top. **A rate limit against a null store is a no-op
      that passes every test you could write for it.**
- [x] **Sign-in is not a user-enumeration oracle** — a missing account verifies against a decoy
      digest, so the three paths cost 219.3 / 219.5 / 219.0 ms. The failure message names neither half.
- [x] **The session is rotated at sign-in** — `reset_session`, carrying the pending authorization
      across deliberately, since that state is why the person is signing in.
- [x] **Rate limits** — sign-in (per address _and_ per identifier, because they stop different
      attacks), second factor, token, registration. Every key tenant-prefixed so one tenant cannot
      exhaust another's budget.
- [x] **Credentials at rest** — passwords and client secrets bcrypt; codes, refresh tokens and
      sessions stored as SHA-256 digests returned once; TOTP secrets and signing keys encrypted. A
      database read recovers no credential.
- [x] **Nothing accumulates forever** — `CleanupJob` sweeps expired and consumed records per tenant
      nightly, with a seven-day grace so a record outlives "why did that fail an hour ago".
- [ ] **CSRF runs before the rate limiter** — so unauthenticated floods are answered 422 rather than 429. Harmless, since both refuse, but the limiter never sees traffic that does not fetch a
      token first.
- [ ] **A device model** — what throttling and captcha policies hang off, and where "sign in on a new
      device" notifications would come from.

## 6. The client gem — masks-client

A client library has two halves, and this shipped one. **Consumers spend tokens; resource servers
accept them.** `Session`, `Registration` and `Issuer` are the first half. The second was one class —
`Verifier`, returning a claims `Hash` — so everything above it gets written by the consumer instead.
The first resource server to adopt this gem wrote its own scope check and its own
`WWW-Authenticate` header _after_ the gem existed, which is the tell.

**The consumer half**

- [x] **Discovery and JWKS, cached** — five minutes, with invalidate-and-refetch on an unknown `kid`,
      so a rotation is picked up without a restart.
- [x] **PKCE authorization URLs, code exchange, refresh, userinfo.**
- [x] **Registration from the client side** — create, read back, and build a session from the result.
- [x] **Exchange and revocation.**
- [x] **An issuer registry, so the cache above is real** — `Issuer` caches in an instance variable
      and `Configuration#session_for` hands `Session.new` a **URL string**, which constructs a fresh
      `Issuer` with an empty cache. The engine therefore makes **two upstream HTTPS calls on every
      authenticated request**, and the box above claiming otherwise has been checked and wrong since
      it was written. Nothing caught it because §7 has never run against a real server. A registry
      keyed by issuer URL fixes it, and is also what makes a subdomain-per-tenant host affordable:
      one `Issuer` per tenant rather than one per request.

**The resource-server half**

- [x] **`Claims` as a value object** — subject, scopes, tenant identity, `client_id`, `act`, expiry,
      and `permits?` / `permit!`. What every resource server writes over `Verifier`'s bare hash.
- [x] **`Resource` — verify a header, refuse a header** — takes `Authorization`, answers `Claims` or
      raises, and builds the `WWW-Authenticate` challenge carrying `resource_metadata` and the
      scopes it would have accepted. The whole handshake for a client handed nothing but a URL.
- [x] **Protected resource metadata — RFC 9728** — generate the
      `/.well-known/oauth-protected-resource` document rather than have each consumer hand-write it.
- [x] **A Rack middleware** — for consumers that want the challenge below the framework rather than
      in a controller. The controller concern in §7 is the Rails-shaped answer; this is the other.
- [ ] **Published to RubyGems** — path-referenced today.

## 7. The Rails engine — masks-rails

- [x] **Mounts, and resolves per request** — issuer, `redirect_uri` and `resource` all accept a
      callable taking the request, so a subdomain-per-tenant host works. Verified by construction.
- [x] **`authenticate_masks!`, `masks_identity`, `masks_tenant`** — with silent refresh when an
      access token has expired and a refresh token is held.
- [x] **A JSON consumer half, so an SPA can use this at all** — `authenticate_masks!` answers every
      refusal with a redirect, and a redirect answered to `fetch()` is either an opaque CORS failure
      or an HTML login page parsed as JSON. The engine assumes the thing being refused is a browser
      navigation. XHR and JSON requests get `401` with a `login_url` instead.
- [x] **`GET /auth/session`** — the SPA bootstrap: identity, tenant and scopes as JSON, or `401` with
      somewhere to send the browser. This is the BFF pattern, and it is the **default** consumer
      path: tokens stay in the encrypted Rails session and never reach JavaScript, so XSS cannot
      lift one and there is no refresh loop in the page.
- [x] **A resource-server concern** — `Masks::Rails::ProtectedResource`, wrapping §6's half for a
      controller. The engine currently offers a consuming app nothing for the tokens it _accepts_.
- [x] **The callback is driven end to end** — start, redirect, code exchange against a signing
      issuer over a socket, `state`, `nonce`, session, and a query on the cookie alone. Twelve tests
      in the first consumer to adopt the engine, which is what it took: the checks were written and
      read for months and never executed. Running them found two defects the reading had not.
- [x] **The id token is read once and not kept** — it was stored in the session with the access and
      refresh tokens, and **three JWTs overflow a 4KB cookie session**: the first real sign-in raised
      `CookieOverflow` at 4247 bytes. Every consumer using the default cookie store would have hit
      it on their first sign-in. The id token is now verified at the callback, six claims are kept,
      and the token is dropped — which also removes a signature verification per request, since
      `masks_identity` was re-verifying it every time it was asked. A consumer whose claims are
      larger still wants a server-side store; the cookie has a hard ceiling and no warning before it.
- [x] **A token response with no `access_token` is refused** — `HTTP.parse` only raises on a non-2xx
      status, so an issuer answering `200` with an error body, or with a body missing the token,
      produced a `Tokens` holding `nil` and a session that looked established. `Tokens.granted`
      refuses both. Found by a fake issuer that answered the wrong status.
- [ ] **The engine's `nonce` check passes vacuously when there is nothing to check** —
      `nonce_matches?` returns true when the id token carries no `nonce` claim, and
      `masks_identity_from` returns `nil` when the response carried no id token at all, which
      short-circuits to the same true. Real against the tokens masks issues, which always carry the
      claim when one was sent, so this is defence in depth rather than a live hole — but the check
      exists precisely for an issuer that is not behaving, and against that issuer it is not a
      check. It should require the claim whenever the request sent one.
- [ ] **Published to RubyGems.**

## 8. The browser package — @masks/client

The fourth deliverable. An SPA is a consumer masks had no story for; the engine cannot serve one
because it redirects. Two modes in one package, serving different consumers rather than competing:

- [x] **BFF session mode** — `session()`, `login()`, `logout()` over `fetch` against §7's
      `/auth/session`. Cookies and CSRF, no tokens in the page. What a same-origin SPA in front of a
      Rails app should use, and the default this package recommends.
- [x] **Browser PKCE mode** — for the consumer that is _not_ a Rails app: a static site, a
      third-party dashboard, anything crossing an origin to reach a resource server. Shipping only
      the BFF would make masks an auth server you can consume only from Rails.
- [x] **S256 over WebCrypto** — `crypto.subtle.digest`, no dependency, no polyfill.
- [x] **`state` checked on callback** — the CSRF half of the pair, and the pending record is
      cleared even when the callback fails, so a forged state cannot be retried against a live
      verifier. Twelve tests drive it.
- [ ] **`nonce` is sent and not verified** — the browser client puts one on the authorization
      request and never checks it back, because checking it means verifying the id token, which
      means JWKS and signature verification in the page. §7 does check it. Until this lands the
      browser mode should be read as "the token is bound to this browser by PKCE and `state`", which
      is true, rather than "the id token is bound to this request", which is not.
- [x] **Tokens in memory; the verifier in `sessionStorage`** — a token lives in a closure and nowhere
      else. `localStorage` survives a tab close and is readable by every script on the origin, and
      buys nothing a silent prompt cannot re-derive. The PKCE verifier and `state` _must_ cross a
      redirect, so they persist — tab-scoped, cleared on callback, and useless without the
      single-use code they pair with.
- [ ] **Silent refresh** — a hidden prompt against the issuer, so the PKCE mode does not have to
      choose between a long-lived token and an interruption.
- [x] **Types generated, ESM only, zero runtime dependencies** — `tsc` emitting declarations; no
      bundler in the chain, because a package this size does not earn one.
- [x] **Linted, typechecked and tested in CI** — biome and `tsc --noEmit`, beside the frontend build that is
      already there.
- [ ] **Published to npm.**

## 9. Docs, CI, packaging

- [x] **Astro + Starlight docs** — sixteen pages, rebuilt against this implementation rather than
      ported from the previous masks.
- [x] **CI** — boundary check, rubocop, brakeman, bundler-audit, docs build, and both gems building.
- [x] **The boundary rule holds** — nothing here names a host, a domain, or a secret.
- [x] **CI runs the test suite** — against a postgres 17 service with the non-superuser `masks` role
      created explicitly, so CI exercises the same role the application uses rather than a
      superuser that would see through every policy.
- [x] **The local equivalent exists now** — `server/bin/ci` over `config/ci.rb`: rubocop, brakeman,
      the gem audit, then the tests. It previously ran `bin/setup` and a gem audit and called that
      CI, which is why this line used to claim a `bin/ci` that ran the same steps as CI when none
      did.
- [x] **CI lints and builds the frontend** — biome over the plain JS, then a real `vite build`.
      **This was checked and could not have passed.** `config/vite.json` and `biome.json` were never
      committed, so on a fresh checkout `npm run lint` and `vite build` had nothing to read — and
      neither did a developer: `bin/vite` was missing too and `bin/setup` never ran `npm install`,
      leaving `logins/show`'s `vite_javascript_tag` pointing at a manifest nobody could build. Both
      configs, the binstub, the `.node-version` CI already read, and a `vite` process in
      `Procfile.dev` are in the tree now.
- [x] **CI boots the way production does** — `zeitwerk:check` under `RAILS_ENV=production` against
      the same non-superuser role. rack-oauth2 arrived with two files the autoloader cannot name:
      `lib/rack/oauth2`, required explicitly by an initializer and not to be autoloaded at all, and
      the `RackOAuth2Endpoint` concern, which zeitwerk reads as `RackOauth2Endpoint`. Neither shows
      in development, where nothing is eager loaded — they show at boot, in the deploy. The
      inflection and the ignore land with the job that would have caught them.
- [x] **A container image** — `server/Dockerfile`, built and run. Multi-stage, non-root, thruster in
      front of puma, solid_queue in the same process. `bin/image` runs it against compose postgres
      and asserts the boot: three databases prepared, both tenants seeded, a distinct `kid` each,
      DCR and RFC 7592 answered, a wrong token and a cross-tenant token both 401. CI builds it on
      every PR and pushes `linux/amd64` to ghcr on `main`.
- [ ] ◐ **Nothing has been deployed with it** — the image runs on a laptop against a compose
      postgres. An external database, a real issuer origin, and TLS at a proxy are all untested, and
      `home` has no inventory yet. `MASKS_PUBLIC_ORIGIN_TEMPLATE` is the seam that has never been set.
- [ ] ◐ **An admin UI** — tenants, actors and clients are managed from the console. §2's setup
      prompt is the first screen of one, built early because installation cannot happen without it;
      `plans/020`'s approval screen is the second, and after that it is tenants and actors.

## 10. Inheritable from the previous masks

All of these exist and work in `masks-mono` or `masks-engine`. Porting is the task, not designing.

- [x] ↧ **The login prompt machine** — ported from `masks-engine/lib/masks/logins`, which is where the
      working one lives; `masks-mono`'s is a stalled rewrite whose `FirstFactorPolicy` is a `# TODO`.
      Rebuilt declaratively (`prompts`/`handles`) in the idiom the old `second_factor.rb` was
      reaching for in comments. **The login flow was never GraphQL** — plain JSON to one endpoint —
      so `graphql-ruby` and `urql` are not part of this.
- [ ] ↧ **WebAuthn** — `masks-mono HardwareKey`, plus `masks-engine/aaguids`. Now a state plus a
      prompt component; the machine it needed is in place.
- [ ] ↧ **Social providers / SSO** — `Provider`, `ClientProvider`, `SingleSignOn`. Note the old
      `identify` step branched on whether an identifier existed; that shape cannot come across
      without reintroducing the enumeration oracle §5 closed.
- [ ] ↧ **Login links** — `LoginLink`. Same caveat as SSO.
- [ ] ↧ **Captcha policies** — `ThrottlePolicy` carries `captcha:`; rate limits cover the throttling
      half already, so what is left to inherit is the captcha challenge itself.
- [ ] ↧ **Devices** — `Device`, and the policy that pairs with throttling.
- [ ] ↧ **The client as the place login policy lives** — the largest thing not carried across, and
      the reason §3 reads thin. `masks-mono`'s `Client` held `seed(key:)` for configured clients,
      `internal` / `oauth` scopes, `required_scopes` **and** `allowed_scopes`, per-client SSO through
      `ClientProvider`, per-client theming (logo, styles, `terms_url`), `*_duration` settings, and a
      per-client login matrix: `allow_passwords`, `allow_sso`, `allow_webauthn`, `allow_otp`,
      `allow_factor2`, `allow_backup_codes`, `allow_login_links`, `allow_signup`, `allow_emails`,
      `allow_nicknames`, `allow_phones`, `allow_profiles`. A client there decided _how you sign in_,
      not merely how a token is issued.
      **Port the scope pair and configured clients now** (§3); hold the rest. The `allow_*` matrix
      is a matrix of one row until WebAuthn, SSO and login links land above, and porting the toggles
      first checks boxes that toggle nothing.
      One thing not to port as-is: `internal?` there meant _masks' own UI_ — `supports_oauth?` was
      `!internal?` and `profile_url` returned a masks login URL. It did not mean "first-party app",
      which is what §3 needs, and reusing the word for the other meaning would be worse than a new
      one.

Worth restating, because the roadmap read upside down: **the previous masks filed WebAuthn, TOTP and
social providers as v2 and had all three written, while none of v1's tenancy, JWKS, registration or
exchange existed anywhere.** The v2 list is mostly a porting exercise.

## 11. Verification

- [x] **A scripted end-to-end run** — the flow at the top of this file, driven with curl against two
      seeded tenants. Repeatable, and it has caught real bugs.
- [x] **A test suite — 166 runs, 410 assertions, from a database built from scratch.** Minitest,
      no fixtures: RLS `WITH CHECK` refuses rows inserted outside a tenant, so every record is
      created inside `Tenant.switch`. Covers first run — claiming, the setup token, and the owner it
      creates — the login machine's transitions and expiries, the
      enumeration properties, tenant isolation and RLS itself, and the login endpoint including
      cross-tenant sign-in. It found the RLS bug in §1 on its first run.
      **None of it was committed until `f8b8e25`** — no `test_helper`, and
      `rails/test_unit/railtie` commented out in `config/application.rb` — so the one test that was
      tracked could not have run on a fresh checkout, and CI's test job could not have passed
      against the tree it was given. The suite was real on this laptop and nowhere else.
- [x] **The two error codes the rack-oauth2 move changed are back** — an unsupported `grant_type`
      answered `invalid_request` where RFC 6749 §5.2 says `unsupported_grant_type`, and a client
      belonging to another tenant answered `invalid_request` where it says `invalid_client`. The
      refusals always refused, so §1's isolation was never in question; what was wrong is the code a
      client reads to tell one refusal from another. Fixed by the authorize work in the tree, which
      is worth having done before the security profile plans at the bottom of this section run.
- [x] **The OIDC surface is now driven in CI, not only by curl** — ten integration tests under
      `test/integration`, built on one `OidcFlow` helper that registers a client, signs in, walks
      authorize → consent → code → token, and verifies the JWT against the tenant's published JWKS.
      Authorize and the code grant, PKCE, refresh rotation, exchange, revocation, registration and
      its management, resource indicators, consent and `prompt`, discovery, JWKS and rotation.
      **It found a real bug on its first run** — see §2's code-consumption item. The scripted curl
      run stays as the check that the _deployed image_ answers; these are the check that a change
      did not break the flow.
- [x] **A conformance harness that drives masks from outside** — `bin/conformance` and
      `conformance/`, standing masks up behind a TLS proxy on a docker network alongside the
      OpenID Foundation suite, and running its published plans through `run-test-plan.py`:
      `oidcc-config-certification-test-plan` for discovery and JWKS, then
      `oidcc-basic-certification-test-plan[client_registration=dynamic_client]` — DCR means the
      suite registers its own clients, so there is no static setup to keep in step. The suite is
      pulled as a prebuilt image at a pinned release rather than built from source. This is the
      answer to "is this actually a correct OIDC provider" that no test we write for ourselves can
      give, because the plans were written against the spec rather than against what we built.
      A nightly workflow, not a PR gate: it wants Java, Mongo and a container build.
- [x] **Both plans have now run to completion, against an image built at `f8b8e25`.** This item
      twice said otherwise. **`oidcc-config-certification-test-plan` is clean** — 2 modules, 35
      conditions, 0 failures, and the one warning is the expected one in `expected-failures.json`.
      **`oidcc-basic-certification-test-plan` is now clean too: all 39 modules, 2178 conditions
      passed, 0 failed, and the only 2 warnings are the expected `tenant` claim.** It went
      2079 / 12 / 9 → 2170 / 4 / 7 → **2178 / 0 / 0 unexpected** over three runs, each one fixing
      what the last found. 30 modules pass outright, 5 skip correctly because masks does not
      implement what they test, and 4 end in `REVIEW` — a screenshot a human signs off for
      certification, with every automated condition in them passing. Nothing is `WAITING`, nothing
      is `INTERRUPTED`, and the run is 90 seconds rather than 580 now that nothing times out. The risk
      this section was built around is retired — HtmlUnit runs the Svelte bundle and drove sign-in
      and consent to a returned code — and so is the other unproven half:
      `MASKS_PUBLIC_ORIGIN_TEMPLATE` and TLS at a proxy were set for the first time and worked.
      What the suite says is wrong is below, and it is the point of having run it.
- [x] ◐ **"Re-authentication never completes" was the wrong reading, and it is worth leaving the
      correction here rather than deleting the claim.** This item said the two modules that hang —
      `oidcc-prompt-login` and `oidcc-max-age-1`, both `WAITING` with no verdict — showed that
      _whenever masks must force a fresh authentication it interrupts and never gets back_, and
      called it the most valuable thing the run produced. It was the most valuable thing only in the
      sense that it was the most alarming. **Both modules block on `ExpectSecondLoginPage`, which
      asks a human to upload a screenshot**; every automated condition in both passes, including
      `auth_time` and, in `oidcc-max-age-1`, all three of
      `CheckIdTokenAuthTimeClaimPresentDueToMaxAge`, `CheckSecondIdTokenAuthTimeIsLaterIfPresent`
      and `CheckIdTokenAuthTimeIsRecentIfPresent` — which is the whole of what masks is responsible
      for. So §2's `prompt=login` and `max_age` boxes were never in doubt, and the `auth_time`
      round-trip fix §2 describes is confirmed from outside rather than merely asserted.
      **A module with no verdict looks identical to a module that failed, and reading the first as
      the second invented a bug that was not there.** The partial mark is honest: the screenshot
      cannot be satisfied headlessly, so these two never go green in an automated run.
- [x] **`oidcc-refresh-token` was refused `offline_access`, and the default was the reason** —
      `CheckIfAuthorizationEndpointError` fired on `invalid_scope`, "this client may not request
      offline_access". A client registering through DCR names no scopes, so it got
      `DEFAULT_SCOPES`, which was `openid profile email` — and then could not ask for the one scope
      that keeps it working without sending the person back through sign-in. The default is now
      `Scopes::STANDARD`, all four. What a client may ask for *beyond* the four is §3's ceiling and
      is unaffected. Passes.
- [x] **The run's findings are fixed, and the re-run confirms them from outside.** Request objects,
      `POST /authorize`, the unreadable refusal, code reuse and the `offline_access` default — each
      is written up where it belongs (§2, §2, §2, §4, above) and each carries an integration test.
      The re-run is what closes them, and it says so specifically: `oidcc-ensure-post-request-succeeds`
      and `oidcc-refresh-token` now pass; `oidcc-codereuse-30seconds` passes; and the two
      request-object modules **skip** rather than fail, which is the correct outcome for a server
      that declares in discovery that it does not support them. The distinction this section exists
      for holds — every one of these was invisible to the 166 tests masks writes for itself until an
      outside suite looked.
- [x] **"The harness cannot finish these headlessly" was wrong twice over, and the suite's own
      source said so.** Four modules were reported as unfinishable — the two `prompt`/`max_age`
      ones and the two redirect-URI ones — on the reasoning that a screenshot needs a human. Reading
      `BrowserControl.java` rather than reasoning about it found both mistakes in ten minutes.
      **A `wait` command takes a sixth argument, `update-image-placeholder-optional`, which fills
      the screenshot placeholder from the page the browser is already looking at** — so the
      screenshot steps automate, and all four modules now finish. And the redirect-URI pair was a
      bug in *our* config, not the suite's behaviour: `Verify Complete` matched
      `*/test/*/callback*`, which `simpleMatch` happily matches against the **authorize** URL,
      because the callback is sitting inside it as the `redirect_uri` query parameter. Anchoring
      the pattern to the suite's own origin fixed it. **Both conclusions were reached by reasoning
      about a component whose source was already checked out in `conformance/.suite`.**
- [x] **The five remaining warnings are gone, and three of them cost real product surface.**
      `EnsureIdTokenDoesNotContainEmailForScopeEmail` twice: **for the code flow `scope=email` asks
      for email at userinfo and not in the id token**, so the id token now carries identity only —
      `sub`, `acr`, `auth_time`, the hashes and `tenant` — and `Masks::Client::Session#identity`
      merges userinfo under the verified id-token claims, which is why §7's engine still has a
      name to show and `things` stays green. `VerifyScopesReturnedInUserInfoClaims` wanted the
      whole standard `profile` set, so `actors` gained ten nullable columns and the seeded owner
      fills them; an actor who has not filled a field still releases nothing.
      `EnsureUserInfoContainsName` wanted a claim asked for by name, which is the `claims` request
      parameter — now supported for userinfo, carried on the code and the access token, with
      `claims_parameter_supported` flipped to true. `acr` is now two honest values,
      `urn:masks:acr:pwd` and `urn:masks:acr:mfa`, advertised in `acr_values_supported` and chosen
      by whether the actor holds a second factor — which the login machine will not settle without,
      so holding one and having used one are the same fact.
      **Worth naming as a cost rather than a win**: ten profile columns and a claims-parameter
      implementation are product surface masks did not otherwise need, added to clear two warnings.
      A profile masks has no UI to edit is a shape worth watching.
- [x] **`expected-failures.json` is how a deliberate divergence stays legible** — each entry names
      the module, the condition, the expected result, and _why_, so a warning that is a decision
      reads differently from a warning that is a bug. What is left in it is the `tenant` claim and
      `resource_indicators_supported` as additive metadata — two warnings on one module, and the
      only two in the whole run. The four screenshot entries stayed after the placeholders were
      automated, because a `REVIEW` is still a human's to sign off at certification.
- [ ] **An OAuth 2.1 / security BCP pass** — the same suite carries security profile plans, which is
      where things like redirect-URI handling and PKCE enforcement get adversarial attention.
      The reason to wait is gone: the basic plan no longer finds correctness bugs, so an adversarial
      plan on top of it would be signal rather than noise. This is the next thing to run here.

## 12. Open

- **Depth and run identity in an exchanged token.** Run supervision wants `run_id`, `root_run_id` and
  `depth` carried by the token, and masks deliberately does not know what a run is. Resolves as
  either a scope the consumer mints and reads back, or a claims extension here. Undecided, and the
  first thing workflows will need.
- **What Claude's custom connector actually sends.** DCR now exists to receive it. Still unobserved,
  and still the riskiest assumption in the whole plan.
- ~~Whether the engine should be the only supported consumer path~~ — **answered: no, and the
  question had the wrong shape.** The first consumer skipped the engine because the engine had
  nothing for a resource server and nothing for an SPA, not because it preferred its own. There are
  three consumer paths and they serve different consumers: the engine for a Rails app,
  `@masks/client` in BFF mode for a same-origin SPA, and `@masks/client` in PKCE mode for a client
  that is neither.
- **Where a browser-mode client learns its `resource` indicator.** The BFF reads it from config; a
  PKCE client has to be told, and getting it wrong yields a token no resource server will accept —
  which is the audience restriction working, presenting as a client that mysteriously cannot call
  anything.
- **Whether `/auth/session` should return scopes.** Convenient for hiding UI, and UI that hides a
  button is not a permission check. Leaning yes, with the constraint restated: the token enforces,
  never the page.
- **Three packages path-referenced across a workspace that is not a repo.** Works on this laptop,
  works in neither CI nor a container build. Publishing is the fix and it is filed in three places.
- **A code that carried no audience lets the token endpoint name any.** `TokensController#narrow`
  refuses a `resource` outside what the code carried — but only `if granted.any?`, so when the
  authorization named no resource at all the requested one is taken as given, and the access token's
  `aud` points at a resource server nobody consented to. Reachable by any registered client of the
  tenant, for any actor who signed in to it. Left as it is because the fix is a choice, not a patch:
  refuse a `resource` the authorization did not carry, or bound it by `clients.resources` — a column
  that exists, is accepted at registration, and is read by nothing. Covered by a test that asserts
  today's behaviour, so whichever way it resolves, the test says so.
- **litellm-style spend metering has no equivalent here** — a token has no budget, only a lifetime.
