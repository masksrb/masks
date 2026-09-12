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
        requirePushedAuthorizationRequests
        events(limit: 25) {
          id action createdAt ipAddress details
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
    }
  `;

  const feedback = createFeedback();

  let client = $state(null);
  let supported = $state([]);
  let name = $state("");
  let logoutUri = $state("");
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
          { term: "Authenticates with", value: client.tokenEndpointAuthMethod, mono: true },
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
      name = data.client?.name ?? "";
      logoutUri = data.client?.backchannelLogoutUri ?? "";
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
        $requirePushedAuthorizationRequests: Boolean
      ) {
        updateClient(
          clientId: $clientId, name: $name, requiredScopes: $requiredScopes,
          allowedScopes: $allowedScopes, backchannelLogoutUri: $backchannelLogoutUri,
          redirectUris: $redirectUris, postLogoutRedirectUris: $postLogoutRedirectUris,
          resources: $resources,
          requirePushedAuthorizationRequests: $requirePushedAuthorizationRequests
        ) {
          client { clientId }
        }
      }`,
      { clientId, ...changes },
      notice,
    );

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
      <Card title="Registration">
        <Field label="Name" bind:value={name} onsave={() => update({ name }, "Renamed.")} />

        <Facts rows={facts} />

        <div class="flex flex-wrap gap-2 pt-1">
          {#if client.tokenEndpointAuthMethod !== "none"}
            <button type="button" class="btn btn-sm" onclick={rotate}>Rotate secret</button>
          {/if}
          {#if !client.archivedAt}
            <button type="button" class="btn btn-sm btn-error btn-outline" onclick={archive}>
              Archive
            </button>
          {/if}
        </div>
      </Card>

      <div class="flex flex-col gap-4">
        <Card
          title="Where it may send people"
          lede="One per line. A redirect URI must be absolute, carry no fragment, and use https unless it is loopback."
        >
          <Lines
            label="Redirect URIs"
            value={client.redirectUris}
            onsave={(redirectUris) => update({ redirectUris }, "Redirect URIs saved.")}
          />

          <Lines
            label="Post-logout redirect URIs"
            value={client.postLogoutRedirectUris}
            hint="Where it may send somebody after signing out."
            onsave={(postLogoutRedirectUris) =>
              update({ postLogoutRedirectUris }, "Post-logout URIs saved.")}
          />

          <Lines
            label="Resources"
            value={client.resources}
            hint="The audiences it may ask a token for."
            onsave={(resources) => update({ resources }, "Resources saved.")}
          />
        </Card>

        <Card title="Always granted" lede="Never shown on a consent screen.">
          <ScopesEditor
            value={client.requiredScopes}
            available={supported}
            onchange={(requiredScopes) => update({ requiredScopes }, "Scopes updated.")}
          />
        </Card>

        <Card title="Granted on request" lede="Everything else it may ask for.">
          <ScopesEditor
            value={client.allowedScopes}
            available={supported}
            onchange={(allowedScopes) => update({ allowedScopes }, "Scopes updated.")}
          />

          {#if client.dynamic}
            <p class="text-sm opacity-70">
              Self-registered, so no <span class="font-mono text-xs">masks:</span> scope.
            </p>
          {/if}
        </Card>

        <Card
          title="Back-channel logout"
          lede="Where to tell this client that a session it was part of has ended."
        >
          <Field
            label="Logout URI"
            bind:value={logoutUri}
            placeholder="https://app.example.com/logout/backchannel"
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
            onsave={() =>
              update(
                { backchannelLogoutUri: logoutUri.trim() || null },
                logoutUri.trim() ? "Saved. Signing out will notify it." : "Cleared.",
              )}
          />

          <p class="text-xs opacity-60">
            A signed logout token is posted there, carrying the subject and the session id, and
            retried for a while if the client does not answer.
          </p>
        </Card>

        <Card
          title="Pushed authorization requests"
          lede="Whether this client has to hand its request to the server before sending anyone here."
        >
          <Switch
            checked={client.requirePushedAuthorizationRequests}
            label="Require a pushed request"
            onchange={(on) =>
              update(
                { requirePushedAuthorizationRequests: on },
                on
                  ? "Required. A plain /authorize link is refused from now on."
                  : "No longer required.",
              )}
          />

          <p class="text-xs opacity-60">
            The client posts the request to <span class="font-mono">/par</span> over its own
            authenticated channel and gets back a one-time
            <span class="font-mono">request_uri</span>, so nothing but that reference travels in the
            browser. Required, an ordinary <span class="font-mono">/authorize</span> link stops
            working, so turn it on once the client is pushing.
          </p>
        </Card>

        <Card title="Who has allowed it in" lede="Cutting somebody off revokes every token it holds for them.">
          <Consents {api} {feedback} rows={client.consents} onchange={load} showActor />
        </Card>

        <Card
          title="Tokens outstanding"
          lede="What this client is holding right now, newest first."
        >
          <Tokens {api} {feedback} rows={client.tokens} onchange={load} showActor />
        </Card>

        <Card title="Activity" lede="What this client has done, and what has been done to it.">
          {#snippet actions()}
            <Link to={`/activity?client=${client.clientId}`} class="btn btn-ghost btn-sm">
              All of it
            </Link>
          {/snippet}

          <Events events={client.events} empty="Nothing recorded for this client yet." />
        </Card>

        {#if client.namespaces.length}
          <Namespaces {api} rows={client.namespaces} onreleased={load} />
        {/if}
      </div>
    </div>
  </Page>
{/if}
