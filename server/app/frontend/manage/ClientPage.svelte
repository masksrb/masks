<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, joined } from "./lib/format.js";
  import Consents from "./Consents.svelte";
  import Events from "./Events.svelte";
  import Namespaces from "./Namespaces.svelte";
  import Tokens from "./Tokens.svelte";
  import ScopesEditor from "./ScopesEditor.svelte";
  import Card from "./ui/Card.svelte";
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
        tokenEndpointAuthMethod applicationType clientUri
        subjectType sectorIdentifierUri
        redirectUris postLogoutRedirectUris grantTypes responseTypes resources
        requiredScopes allowedScopes
        backchannelLogoutUri backchannelLogoutSessionRequired
        requirePushedAuthorizationRequests requireSignedRequestObject consentRequired jwks jwksUri
        signInPolicy { key name }
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
      signInPolicies { key name }
      tenant { signInPolicy { key name } }
    }
  `;

  const feedback = createFeedback();

  let client = $state(null);
  let supported = $state([]);
  let policies = $state([]);
  let tenantPolicy = $state(null);
  let name = $state("");
  let logoutUri = $state("");
  let jwksUri = $state("");
  let method = $state("");
  let loading = $state(true);
  let secret = $state(null);

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
          { term: "Knows people as", value: client.subjectType, mono: true },
          { term: "Sector", value: client.sectorIdentifierUri, mono: true },
        ]
      : [],
  );

  async function load() {
    loading = true;

    try {
      const data = await api.query(QUERY, { clientId });

      client = data.client;
      supported = data.scopesSupported;
      policies = data.signInPolicies;
      tenantPolicy = data.tenant.signInPolicy;
      name = data.client?.name ?? "";
      logoutUri = data.client?.backchannelLogoutUri ?? "";
      jwksUri = data.client?.jwksUri ?? "";
      method = data.client?.tokenEndpointAuthMethod ?? "";
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
        $tokenEndpointAuthMethod: String, $requireSignedRequestObject: Boolean
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
          requireSignedRequestObject: $requireSignedRequestObject
        ) {
          client { clientId }
        }
      }`,
      { clientId, ...changes },
      notice,
    );

  const unattended = $derived(client?.grantTypes.includes("client_credentials") ?? false);

  function signsInAsItself(on) {
    const grantTypes = on
      ? [...client.grantTypes, "client_credentials"]
      : client.grantTypes.filter((grant) => grant !== "client_credentials");

    update(
      { grantTypes },
      on
        ? "It can ask for a token of its own now, with client_credentials."
        : "It can no longer ask for a token of its own.",
    );
  }

  const METHODS = [
    ["client_secret_basic", "Secret, in a Basic header"],
    ["client_secret_post", "Secret, in the form"],
    ["private_key_jwt", "An assertion signed with its own key"],
  ];

  function authenticates(chosen) {
    method = chosen;

    if (chosen === "private_key_jwt" && !client.jwksUri) return;

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

          {#if client.tokenEndpointAuthMethod === "none"}
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

          {#if method === "private_key_jwt"}
            <Field
              label="Key set URL (jwks_uri)"
              bind:value={jwksUri}
              placeholder="https://app.example.com/.well-known/jwks.json"
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              onsave={() =>
                update(
                  { jwksUri: jwksUri.trim() || null, tokenEndpointAuthMethod: method },
                  "Its keys are read from there.",
                )}
            />
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

        <Card title="Sign-in">
          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium opacity-70">Policy</span>
            <select
              class="select select-sm w-full"
              value={client.signInPolicy?.key ?? ""}
              onchange={(event) =>
                update({ signInPolicy: event.currentTarget.value }, "Policy updated.")}
            >
              <option value="">Default ({tenantPolicy?.name ?? "built-in"})</option>
              {#each policies as policy (policy.key)}
                <option value={policy.key}>{policy.name}</option>
              {/each}
            </select>
          </label>

          <Switch
            checked={client.requirePushedAuthorizationRequests}
            label="Require pushed requests (PAR)"
            onchange={(on) =>
              update(
                { requirePushedAuthorizationRequests: on },
                on ? "PAR required. Plain /authorize links are refused." : "PAR optional.",
              )}
          />

          {#if client.jwks || client.jwksUri}
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
        </Card>

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
            label="Redirect"
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
