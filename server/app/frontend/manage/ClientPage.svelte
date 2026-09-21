<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, joined } from "./lib/format.js";
  import { POLICY_FIELDS, policyDifferences } from "./lib/policies.js";
  import Consents from "./Consents.svelte";
  import Events from "./Events.svelte";
  import Namespaces from "./Namespaces.svelte";
  import Tokens from "./Tokens.svelte";
  import ScopesEditor from "./ScopesEditor.svelte";
  import Card from "./ui/Card.svelte";
  import ClientLogo from "./ui/ClientLogo.svelte";
  import Facts from "./ui/Facts.svelte";
  import Field from "./ui/Field.svelte";
  import Switch from "./ui/Switch.svelte";
  import Lines from "./ui/Lines.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api, clientId } = $props();

  const QUERY = `
    query Client($clientId: ID!) {
      client(clientId: $clientId) {
        clientId name dynamic approvedAt archivedAt secretExpiresAt createdAt
        tokenEndpointAuthMethod applicationType clientUri logoUri tosUri policyUri logoUrl(size: 128)
        subjectType sectorIdentifierUri
        redirectUris postLogoutRedirectUris grantTypes responseTypes resources
        requiredScopes allowedScopes
        backchannelLogoutUri backchannelLogoutSessionRequired
        requirePushedAuthorizationRequests requireSignedRequestObject consentRequired jwks jwksUri
        protocol samlEntityId samlCertificate samlNameIdFormat samlRequestsSigned samlIdpInitiated samlAttributes
        signInPolicy { ${POLICY_FIELDS} }
        events(limit: 25) {
          id action label createdAt ipAddress details
          actor { uuid identifier }
          by { uuid identifier }
          device { id label }
        }
        approvedBy { identifier }
        namespaces { name resource claimedAt releasable }
        consents(limit: 25) {
          id scopes audience updatedAt
          actor { uuid identifier }
        }
        tokens(limit: 25) {
          id kind scopes audience parentId createdAt expiresAt
          actor { uuid identifier }
          device { id label }
        }
      }
      scopesSupported
      samlMetadataUrl
      signInPolicies { key name }
      defaultSignInPolicy { ${POLICY_FIELDS} }
    }
  `;

  const feedback = createFeedback();

  let client = $state(null);
  let supported = $state([]);
  let policies = $state([]);
  let fallbackPolicy = $state(null);
  let name = $state("");
  let logoutUri = $state("");
  let jwksUri = $state("");
  let jwks = $state("");
  let method = $state("");
  let sector = $state("");
  let metadataUrl = $state("");
  let certificate = $state("");
  let entityId = $state("");
  let links = $state({});
  let attributes = $state("");
  let loading = $state(true);
  let secret = $state(null);

  const NAME_IDS = [
    ["urn:oasis:names:tc:SAML:2.0:nameid-format:persistent", "A persistent identifier"],
    ["urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress", "Their email"],
  ];

  const saml = $derived(client?.protocol === "saml");

  const facts = $derived(
    client
      ? [
          {
            term: "How it got here",
            value: client.dynamic ? "self-registered" : "approved",
          },
          { term: "Approved by", value: client.approvedBy?.identifier },
          { term: "Registered", value: day(client.createdAt) },
          { term: "Grants", value: joined(client.grantTypes), mono: true },
          { term: "Response types", value: joined(client.responseTypes), mono: true },
        ]
      : [],
  );

  const SUBJECTS = [
    ["public", "The same identifier every client sees (public)"],
    ["pairwise", "An identifier only it knows (pairwise)"],
  ];

  const GRANTS = [
    ["refresh_token", "Keeps people signed in (refresh tokens)"],
    ["urn:ietf:params:oauth:grant-type:device_code", "Signs in on devices without a browser (device code)"],
    ["urn:ietf:params:oauth:grant-type:token-exchange", "Swaps one token for another (token exchange)"],
  ];

  const LINKS = [
    ["logoUri", "Logo URL", "https://app.example.com/logo.png", "The logo is being fetched. It shows here in a moment."],
    ["clientUri", "Home page", "https://app.example.com", "Home page saved."],
    ["tosUri", "Terms of service", "https://app.example.com/terms", "Terms saved."],
    ["policyUri", "Privacy policy", "https://app.example.com/privacy", "Privacy policy saved."],
  ];

  async function saveLink(key, notice) {
    const value = links[key].trim();

    await update({ [key]: value || null }, value ? notice : "Cleared.");

    if (key === "logoUri" && value) setTimeout(load, 3000);
  }

  const SAML_DEFAULTS = "email = email\nname = name\ngiven_name = given_name\nfamily_name = family_name\npreferred_username = preferred_username";

  const differences = $derived(
    client?.signInPolicy && fallbackPolicy ? policyDifferences(client.signInPolicy, fallbackPolicy) : [],
  );

  const keyed = $derived(Boolean(client?.jwks || client?.jwksUri));

  const mapped = (held) =>
    Object.entries(held ?? {})
      .map(([attribute, claim]) => `${attribute} = ${claim}`)
      .join("\n");

  async function load() {
    loading = true;

    try {
      const data = await api.query(QUERY, { clientId });

      client = data.client;
      supported = data.scopesSupported;
      policies = data.signInPolicies;
      fallbackPolicy = data.defaultSignInPolicy;
      name = data.client?.name ?? "";
      logoutUri = data.client?.backchannelLogoutUri ?? "";
      jwksUri = data.client?.jwksUri ?? "";
      jwks = data.client?.jwks ? JSON.stringify(data.client.jwks, null, 2) : "";
      method = data.client?.tokenEndpointAuthMethod ?? "";
      sector = data.client?.sectorIdentifierUri ?? "";
      metadataUrl = data.samlMetadataUrl;
      certificate = data.client?.samlCertificate ?? "";
      entityId = data.client?.samlEntityId ?? "";
      links = Object.fromEntries(LINKS.map(([key]) => [key, data.client?.[key] ?? ""]));
      attributes = mapped(data.client?.samlAttributes);
    } catch (thrown) {
      feedback.blame(thrown);
    } finally {
      loading = false;
    }
  }

  load();

  async function act(document, variables, notice) {
    const data = await feedback.attempt(() => api.query(document, variables), notice);

    if (data) await load();

    return data;
  }

  const update = (changes, notice) =>
    act(
      `mutation Update(
        $clientId: ID!, $name: String, $requiredScopes: [String!], $allowedScopes: [String!],
        $backchannelLogoutUri: String, $redirectUris: [String!],
        $postLogoutRedirectUris: [String!], $resources: [String!],
        $requirePushedAuthorizationRequests: Boolean, $consentRequired: Boolean,
        $signInPolicy: ID, $grantTypes: [String!], $jwksUri: String,
        $tokenEndpointAuthMethod: String, $requireSignedRequestObject: Boolean,
        $samlCertificate: String, $samlRequestsSigned: Boolean, $samlIdpInitiated: Boolean,
        $samlNameIdFormat: String, $samlEntityId: String, $samlAttributes: JSON, $jwks: JSON,
        $subjectType: String, $sectorIdentifierUri: String, $dpopBoundAccessTokens: Boolean,
        $backchannelLogoutSessionRequired: Boolean, $clientUri: String, $logoUri: String,
        $tosUri: String, $policyUri: String
      ) {
        updateClient(
          clientId: $clientId, name: $name, requiredScopes: $requiredScopes,
          allowedScopes: $allowedScopes, backchannelLogoutUri: $backchannelLogoutUri,
          redirectUris: $redirectUris, postLogoutRedirectUris: $postLogoutRedirectUris,
          resources: $resources,
          requirePushedAuthorizationRequests: $requirePushedAuthorizationRequests,
          consentRequired: $consentRequired,
          signInPolicy: $signInPolicy,
          grantTypes: $grantTypes,
          jwksUri: $jwksUri,
          tokenEndpointAuthMethod: $tokenEndpointAuthMethod,
          requireSignedRequestObject: $requireSignedRequestObject,
          samlCertificate: $samlCertificate,
          samlRequestsSigned: $samlRequestsSigned,
          samlIdpInitiated: $samlIdpInitiated,
          samlNameIdFormat: $samlNameIdFormat,
          samlEntityId: $samlEntityId,
          samlAttributes: $samlAttributes,
          jwks: $jwks,
          subjectType: $subjectType,
          sectorIdentifierUri: $sectorIdentifierUri,
          dpopBoundAccessTokens: $dpopBoundAccessTokens,
          backchannelLogoutSessionRequired: $backchannelLogoutSessionRequired,
          clientUri: $clientUri,
          logoUri: $logoUri,
          tosUri: $tosUri,
          policyUri: $policyUri
        ) {
          client { clientId }
        }
      }`,
      { clientId, ...changes },
      notice,
    );

  const unattended = $derived(client?.grantTypes.includes("client_credentials") ?? false);

  const granting = (grant, on) =>
    on ? [...new Set([...client.grantTypes, grant])] : client.grantTypes.filter((held) => held !== grant);

  function signsInAsItself(on) {
    update(
      { grantTypes: granting("client_credentials", on) },
      on
        ? "It can ask for a token of its own now, with client_credentials."
        : "It can no longer ask for a token of its own.",
    );
  }

  function knowsPeopleAs(chosen) {
    const question =
      "Everybody gets a different identifier at this client. It will not recognise anybody it already knows. Change it?";

    if (chosen === client.subjectType || !confirm(question)) {
      load();
      return;
    }

    update({ subjectType: chosen }, "Saved. Everybody has a new identifier at this client.");
  }

  function saveKeys(held) {
    const pending = method === "private_key_jwt" && client.tokenEndpointAuthMethod !== "private_key_jwt";
    const changes = pending ? { ...held, tokenEndpointAuthMethod: method } : held;

    update(changes, pending ? "Its keys are saved, and it signs its own assertions now." : "Keys saved.");
  }

  function saveKeySet() {
    const text = jwks.trim();

    if (!text) {
      saveKeys({ jwks: null });
      return;
    }

    try {
      saveKeys({ jwks: JSON.parse(text), jwksUri: null });
    } catch {
      feedback.blame(new Error("That key set is not JSON."));
    }
  }

  function saveAttributes() {
    const pairs = attributes
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => line.split("=").map((part) => part.trim()));

    if (pairs.some((pair) => pair.length !== 2 || !pair[0] || !pair[1])) {
      feedback.blame(new Error("Write one attribute = claim on each line."));
      return;
    }

    update(
      { samlAttributes: Object.fromEntries(pairs) },
      pairs.length ? "Attributes saved." : "It is sent the usual attributes.",
    );
  }

  const METHODS = [
    ["client_secret_basic", "Secret, in a Basic header"],
    ["client_secret_post", "Secret, in the form"],
    ["private_key_jwt", "An assertion signed with its own key"],
  ];

  function authenticates(chosen) {
    method = chosen;

    if (chosen === "private_key_jwt" && !keyed) return;

    const notice =
      chosen === "private_key_jwt"
        ? "It signs its own assertions now. Its secret no longer works."
        : client.tokenEndpointAuthMethod === "private_key_jwt"
          ? "It uses a secret now. Rotate one to hand it."
          : "Saved.";

    update({ tokenEndpointAuthMethod: chosen }, notice);
  }

  function restore() {
    if (!confirm("Restore this client? It can sign people in again immediately.")) return;

    act(
      `mutation Restore($clientId: ID!) {
        restoreClient(clientId: $clientId) { client { archivedAt } }
      }`,
      { clientId },
      "Restored.",
    );
  }

  async function rotate() {
    if (!confirm("Issue a new secret? The one in use stops working immediately.")) return;

    const data = await act(
      `mutation Rotate($clientId: ID!) { rotateClientSecret(clientId: $clientId) { secret } }`,
      { clientId },
      "A new secret was issued.",
    );

    if (data) secret = data.rotateClientSecret.secret;
  }

  function archive() {
    if (!confirm("Archive this client? Nothing will be able to sign in with it.")) return;

    act(
      `mutation Archive($clientId: ID!) { archiveClient(clientId: $clientId) { client { archivedAt } } }`,
      { clientId },
      "Archived.",
    );
  }
</script>

{#if loading && !client}
  <Spinner />
{:else if !client}
  <div class="alert alert-error alert-soft text-sm" role="alert">
    {feedback.state.failure ?? "There is no client with that id."}
  </div>
{:else}
  <Page title={client.name} id={client.clientId} back={{ to: "/clients", label: "Clients" }}>
    <Notices feedback={feedback.state} />

    {#if client.archivedAt}
      <div class="alert alert-warning alert-soft flex-wrap items-center gap-3 text-sm" role="status">
        <span>Archived on {day(client.archivedAt)}. It can no longer sign anybody in.</span>
        <button type="button" class="btn btn-sm" onclick={restore}>Restore it</button>
      </div>
    {/if}

    {#if secret}
      <div class="alert alert-warning alert-soft flex-col items-start gap-2" role="status">
        <span class="font-medium">This secret is shown once. Copy it now.</span>
        <code class="font-mono text-sm break-all">{secret}</code>
      </div>
    {/if}

    <div class="grid items-start gap-4 md:grid-cols-2">
      <div class="flex flex-col gap-4">
        <Card title="Registration">
          <Field label="Name" bind:value={name} onsave={() => update({ name }, "Renamed.")} />

          <Facts rows={facts} />

          {#if saml}
            <p class="text-xs opacity-60">A SAML application. It is signed into with an assertion, not a token.</p>
          {:else if client.tokenEndpointAuthMethod === "none"}
            <p class="text-xs opacity-60">A public client. It authenticates with nothing, and proves itself with PKCE.</p>
          {:else}
            <label class="flex flex-col gap-1.5">
              <span class="text-xs font-medium opacity-70">Authenticates with</span>
              <select
                class="select select-sm w-full"
                value={method}
                onchange={(event) => authenticates(event.currentTarget.value)}
              >
                {#each METHODS as [key, label] (key)}
                  <option value={key}>{label}</option>
                {/each}
              </select>
            </label>
          {/if}

          {#if method === "private_key_jwt" && !keyed}
            <p class="text-xs text-warning">Give it keys under Keys, and it switches to signing its own assertions.</p>
          {/if}

          {#if !saml}
            <label class="flex flex-col gap-1.5">
              <span class="text-xs font-medium opacity-70">Knows people as</span>
              <select
                class="select select-sm w-full"
                value={client.subjectType}
                onchange={(event) => knowsPeopleAs(event.currentTarget.value)}
              >
                {#each SUBJECTS as [key, label] (key)}
                  <option value={key}>{label}</option>
                {/each}
              </select>
            </label>

            {#if client.subjectType === "pairwise" || client.sectorIdentifierUri}
              <Field
                label="Sector identifier URI"
                bind:value={sector}
                placeholder="needed when its redirect URIs span several hosts"
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
                onsave={() =>
                  update({ sectorIdentifierUri: sector.trim() || null }, sector.trim() ? "Saved." : "Cleared.")}
              />
            {/if}

            {#each GRANTS as [grant, label] (grant)}
              <Switch
                checked={client.grantTypes.includes(grant)}
                {label}
                onchange={(on) => update({ grantTypes: granting(grant, on) }, "Grants updated.")}
              />
            {/each}
          {/if}

          {#if client.approvedAt && client.tokenEndpointAuthMethod !== "none"}
            <Switch
              checked={unattended}
              label="Signs in as itself (client_credentials)"
              onchange={signsInAsItself}
            />
          {/if}

          <div class="flex flex-wrap gap-2 pt-1">
            {#if client.tokenEndpointAuthMethod.startsWith("client_secret")}
              <button type="button" class="btn btn-sm" onclick={rotate}>Rotate secret</button>
            {/if}
            {#if !client.archivedAt}
              <button type="button" class="btn btn-sm btn-error btn-outline" onclick={archive}>
                Archive
              </button>
            {/if}
          </div>
        </Card>

        {#if saml}
          <Card title="SAML">
            <Field
              label="Entity ID"
              bind:value={entityId}
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              onsave={() => update({ samlEntityId: entityId.trim() }, "Entity ID saved.")}
            />

            <Facts
              rows={[
                { term: "masks metadata", value: metadataUrl, mono: true },
                { term: "Start from masks", value: client.samlIdpInitiated ? `/saml/initiate/${client.clientId}` : null, mono: true },
              ]}
            />

            <label class="flex flex-col gap-1.5">
              <span class="text-xs font-medium opacity-70">Names people by</span>
              <select
                class="select select-sm w-full"
                value={client.samlNameIdFormat ?? NAME_IDS[0][0]}
                onchange={(event) => update({ samlNameIdFormat: event.currentTarget.value }, "Saved.")}
              >
                {#each NAME_IDS as [format, label] (format)}
                  <option value={format}>{label}</option>
                {/each}
              </select>
            </label>

            <label class="flex flex-col gap-1.5">
              <span class="text-xs font-medium opacity-70">Its signing certificate</span>
              <textarea
                class="textarea textarea-sm w-full font-mono text-xs"
                rows="3"
                spellcheck="false"
                bind:value={certificate}
              ></textarea>
              <button
                type="button"
                class="btn btn-sm self-start"
                onclick={() => update({ samlCertificate: certificate.trim() }, certificate.trim() ? "Certificate saved." : "Certificate removed.")}
              >
                Save
              </button>
            </label>

            <label class="flex flex-col gap-1.5">
              <span class="text-xs font-medium opacity-70">Attributes it is sent, one attribute = claim a line</span>
              <textarea
                class="textarea textarea-sm w-full font-mono text-xs"
                rows="5"
                spellcheck="false"
                placeholder={SAML_DEFAULTS}
                bind:value={attributes}
              ></textarea>
              <span class="text-xs opacity-60">Left empty, it is sent the ones shown. An email is sent only once confirmed.</span>
              <button type="button" class="btn btn-sm self-start" onclick={saveAttributes}>Save</button>
            </label>

            <Switch
              checked={client.samlRequestsSigned}
              label="Refuse requests it did not sign"
              onchange={(on) =>
                update({ samlRequestsSigned: on }, on ? "Unsigned requests are refused." : "Unsigned requests are read.")}
            />

            <Switch
              checked={client.samlIdpInitiated}
              label="Let people start from masks"
              onchange={(on) =>
                update(
                  { samlIdpInitiated: on },
                  on
                    ? "People can be signed into it from masks, without it asking."
                    : "It is signed into only when it asks.",
                )}
            />
          </Card>
        {/if}

        <Card title="Shown to people">
          <div class="flex items-center gap-3">
            <ClientLogo {client} class="size-14 rounded-lg border border-base-300 text-xl" />
            <p class="text-xs opacity-60">
              {#if !client.approvedAt}
                Nobody sees its logo until it is approved: a client that registered itself could borrow anybody's.
              {:else}
                Its logo, and these links, are shown when people are asked to let it in.
              {/if}
            </p>
          </div>

          {#each LINKS as [key, label, placeholder, notice] (key)}
            <Field
              {label}
              bind:value={links[key]}
              {placeholder}
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              onsave={() => saveLink(key, notice)}
            />
          {/each}
        </Card>

        <Card title="Sign-in">
          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium opacity-70">Policy</span>
            <select
              class="select select-sm w-full"
              value={client.signInPolicy?.key ?? ""}
              onchange={(event) =>
                update({ signInPolicy: event.currentTarget.value }, "Policy updated.")}
            >
              <option value="">Default ({fallbackPolicy?.name ?? "built-in"})</option>
              {#each policies as policy (policy.key)}
                <option value={policy.key}>{policy.name}</option>
              {/each}
            </select>
          </label>

          {#if client.signInPolicy?.archivedAt}
            <p class="text-xs text-warning">
              {client.signInPolicy.name} is archived, so {fallbackPolicy?.name} applies instead.
            </p>
          {:else if client.signInPolicy}
            {#if differences.length}
              <div class="flex flex-col gap-1.5">
                <span class="text-xs font-medium opacity-70">Where it differs from {fallbackPolicy?.name}</span>
                <dl class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
                  {#each differences as { term, value, instead } (term)}
                    <dt class="opacity-60">{term}</dt>
                    <dd>{value} <span class="opacity-50 line-through">{instead}</span></dd>
                  {/each}
                </dl>
              </div>
            {:else}
              <p class="text-xs opacity-60">The same as {fallbackPolicy?.name} in every way.</p>
            {/if}
          {/if}

          {#if !saml}
          <Switch
            checked={client.requirePushedAuthorizationRequests}
            label="Require pushed requests (PAR)"
            onchange={(on) =>
              update(
                { requirePushedAuthorizationRequests: on },
                on ? "PAR required. Plain /authorize links are refused." : "PAR optional.",
              )}
          />

          <Switch
            checked={client.dpopBoundAccessTokens}
            label="Bind its access tokens to a key (DPoP)"
            onchange={(on) =>
              update(
                { dpopBoundAccessTokens: on },
                on ? "Its access tokens are bound to its key. A token without a proof is refused." : "Bearer tokens.",
              )}
          />
          {/if}

          {#if client.approvedAt}
            <Switch
              checked={client.consentRequired}
              label="Ask people to consent"
              onchange={(on) =>
                update(
                  { consentRequired: on },
                  on
                    ? "Consent required. Each person approves what this client asks for."
                    : "Consent skipped. Nobody is asked before this client is granted access.",
                )}
            />
          {/if}

          <Field
            label="Back-channel logout URI"
            bind:value={logoutUri}
            placeholder="https://app.example.com/logout"
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
            onsave={() =>
              update({ backchannelLogoutUri: logoutUri.trim() || null }, logoutUri.trim() ? "Saved." : "Cleared.")}
          />

          {#if client.backchannelLogoutUri}
            <Switch
              checked={client.backchannelLogoutSessionRequired}
              label="Its logout token names the session (sid)"
              onchange={(on) => update({ backchannelLogoutSessionRequired: on }, "Saved.")}
            />
          {/if}
        </Card>

        {#if !saml}
          <Card title="Keys">
            <p class="text-xs opacity-60">
              What masks checks its signed assertions (private_key_jwt) and signed requests (JAR) against. A URL or the
              key set itself, not both.
            </p>

            <Field
              label="Key set URL (jwks_uri)"
              bind:value={jwksUri}
              placeholder="https://app.example.com/.well-known/jwks.json"
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              onsave={() => saveKeys(jwksUri.trim() ? { jwksUri: jwksUri.trim(), jwks: null } : { jwksUri: null })}
            />

            <label class="flex flex-col gap-1.5">
              <span class="text-xs font-medium opacity-70">Or the key set (JWKS)</span>
              <textarea
                class="textarea textarea-sm w-full font-mono text-xs"
                rows="4"
                spellcheck="false"
                placeholder={'{ "keys": [ ... ] }'}
                bind:value={jwks}
              ></textarea>
              <button type="button" class="btn btn-sm self-start" onclick={saveKeySet}>Save</button>
            </label>

            {#if keyed}
              <Switch
                checked={client.requireSignedRequestObject}
                label="Require signed request objects (JAR)"
                onchange={(on) =>
                  update(
                    { requireSignedRequestObject: on },
                    on
                      ? "Signed requests required. An unsigned /authorize or pushed request is refused."
                      : "Signed requests optional.",
                  )}
              />
            {/if}
          </Card>
        {/if}

        <Card title="Scopes">
          <div class="flex flex-col gap-1.5">
            <span class="text-xs font-medium opacity-70">Always granted</span>
            <ScopesEditor
              value={client.requiredScopes}
              available={supported}
              onchange={(requiredScopes) => update({ requiredScopes }, "Scopes updated.")}
            />
          </div>

          <div class="flex flex-col gap-1.5">
            <span class="text-xs font-medium opacity-70">On request</span>
            <ScopesEditor
              value={client.allowedScopes}
              available={supported}
              onchange={(allowedScopes) => update({ allowedScopes }, "Scopes updated.")}
            />
          </div>
        </Card>
      </div>

      <div class="flex flex-col gap-4">
        <Card title="URIs">
          <Lines
            label={saml ? "Assertion consumer services" : "Redirect"}
            value={client.redirectUris}
            onsave={(redirectUris) => update({ redirectUris }, "Redirect URIs saved.")}
          />

          <Lines
            label="Post-logout redirect"
            value={client.postLogoutRedirectUris}
            onsave={(postLogoutRedirectUris) =>
              update({ postLogoutRedirectUris }, "Post-logout URIs saved.")}
          />

          <Lines
            label="Resources"
            value={client.resources}
            onsave={(resources) => update({ resources }, "Resources saved.")}
          />
        </Card>

        <Card title="Consents">
          <Consents {api} {feedback} rows={client.consents} onchange={load} showActor />
        </Card>

        <Card title="Tokens">
          <Tokens {api} {feedback} rows={client.tokens} onchange={load} showActor />
        </Card>

        <Card title="Activity">
          {#snippet actions()}
            <Link to={`/activity?client=${client.clientId}`} class="btn btn-ghost btn-sm">All activity</Link>
          {/snippet}

          <Events events={client.events} empty="Nothing yet." />
        </Card>

        {#if client.namespaces.length}
          <Namespaces {api} rows={client.namespaces} onreleased={load} />
        {/if}
      </div>
    </div>
  </Page>
{/if}
