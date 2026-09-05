<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, joined } from "./lib/format.js";
  import ScopesEditor from "./ScopesEditor.svelte";
  import Card from "./ui/Card.svelte";
  import Facts from "./ui/Facts.svelte";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api, clientId } = $props();

  const QUERY = `
    query Client($clientId: ID!) {
      client(clientId: $clientId) {
        clientId name dynamic approvedAt archivedAt secretExpiresAt createdAt
        tokenEndpointAuthMethod applicationType clientUri
        redirectUris postLogoutRedirectUris grantTypes responseTypes resources
        requiredScopes allowedScopes
        approvedBy { nickname }
      }
      scopesSupported
    }
  `;

  const feedback = createFeedback();

  let client = $state(null);
  let supported = $state([]);
  let name = $state("");
  let loading = $state(true);
  let secret = $state(null);

  const facts = $derived(
    client
      ? [
          {
            term: "How it got here",
            value: client.dynamic ? "self-registered" : "approved",
          },
          { term: "Approved by", value: client.approvedBy?.nickname },
          { term: "Registered", value: day(client.createdAt) },
          { term: "Authenticates with", value: client.tokenEndpointAuthMethod, mono: true },
          { term: "Resources", value: joined(client.resources), mono: true },
          { term: "Redirect URIs", value: joined(client.redirectUris), mono: true },
          { term: "Grants", value: joined(client.grantTypes), mono: true },
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
      `mutation Update($clientId: ID!, $name: String, $requiredScopes: [String!], $allowedScopes: [String!]) {
        updateClient(clientId: $clientId, name: $name, requiredScopes: $requiredScopes, allowedScopes: $allowedScopes) {
          client { clientId }
        }
      }`,
      { clientId, ...changes },
      notice,
    );

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
      <div class="alert alert-warning alert-soft text-sm" role="status">
        Archived on {day(client.archivedAt)}. It can no longer sign anybody in.
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
          title="Always granted"
          lede="Held whether or not the client asks for them, and never shown on a consent screen."
        >
          <ScopesEditor
            value={client.requiredScopes}
            available={supported}
            onchange={(requiredScopes) => update({ requiredScopes }, "Scopes updated.")}
          />
        </Card>

        <Card
          title="Granted on request"
          lede="Everything else this client may ask for. Together with the set above, this is the ceiling it is refused outside."
        >
          <ScopesEditor
            value={client.allowedScopes}
            available={supported}
            onchange={(allowedScopes) => update({ allowedScopes }, "Scopes updated.")}
          />

          {#if client.dynamic}
            <p class="text-sm opacity-70">
              Nobody approved this client, so it may not hold a
              <span class="font-mono text-xs">masks:</span> scope.
            </p>
          {/if}
        </Card>
      </div>
    </div>
  </Page>
{/if}
