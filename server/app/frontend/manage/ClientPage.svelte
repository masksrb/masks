<script>
  import ScopesEditor from "./ScopesEditor.svelte";

  let { api, clientId, router } = $props();

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

  let client = $state(null);
  let supported = $state([]);
  let name = $state("");
  let loading = $state(true);
  let notice = $state(null);
  let failure = $state(null);
  let secret = $state(null);

  async function load() {
    loading = true;

    try {
      const data = await api.query(QUERY, { clientId });

      client = data.client;
      supported = data.scopesSupported;
      name = data.client?.name ?? "";
    } catch (thrown) {
      failure = thrown.message;
    } finally {
      loading = false;
    }
  }

  load();

  async function act(document, variables, message) {
    notice = null;
    failure = null;

    try {
      const data = await api.query(document, variables);
      notice = message;
      await load();

      return data;
    } catch (thrown) {
      failure = thrown.message;

      return null;
    }
  }

  const update = (changes, message) =>
    act(
      `mutation Update($clientId: ID!, $name: String, $requiredScopes: [String!], $allowedScopes: [String!]) {
        updateClient(clientId: $clientId, name: $name, requiredScopes: $requiredScopes, allowedScopes: $allowedScopes) {
          client { clientId }
        }
      }`,
      { clientId, ...changes },
      message,
    );

  async function rotate() {
    if (!confirm("Issue a new secret? The current one stops working immediately.")) return;

    const data = await act(
      `mutation Rotate($clientId: ID!) { rotateClientSecret(clientId: $clientId) { secret } }`,
      { clientId },
      "A new secret was issued. It is shown once.",
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

<button class="btn btn-ghost btn-sm mb-4" onclick={() => router.go("/clients")}>← Clients</button>

{#if loading && !client}
  <div class="py-16 grid place-items-center"><span class="loading loading-spinner"></span></div>
{:else if !client}
  <div class="alert alert-error text-sm" role="alert">{failure ?? "No client with that id."}</div>
{:else}
  <h1 class="text-xl font-bold mb-1">{client.name}</h1>
  <p class="text-xs opacity-60 font-mono mb-4">{client.clientId}</p>

  {#if notice}<div class="alert alert-success text-sm mb-4">{notice}</div>{/if}
  {#if failure}<div class="alert alert-error text-sm mb-4" role="alert">{failure}</div>{/if}

  {#if secret}
    <div class="alert alert-warning flex-col items-start gap-2 mb-4">
      <span class="font-medium">This secret is shown once.</span>
      <code class="font-mono text-sm break-all">{secret}</code>
    </div>
  {/if}

  {#if client.archivedAt}
    <div class="alert alert-error text-sm mb-4">Archived {client.archivedAt.slice(0, 10)}.</div>
  {/if}

  <div class="grid md:grid-cols-2 gap-4 items-start">
    <section class="card bg-base-100">
      <div class="card-body gap-3">
        <h2 class="card-title text-base">Registration</h2>

        <label class="form-control">
          <span class="label-text text-xs opacity-70">Name</span>
          <div class="join">
            <input class="input input-sm input-bordered join-item w-full" bind:value={name} />
            <button class="btn btn-sm join-item" onclick={() => update({ name }, "Renamed.")}>Save</button>
          </div>
        </label>

        <dl class="text-sm grid grid-cols-3 gap-y-2">
          <dt class="opacity-60">Kind</dt>
          <dd class="col-span-2">{client.dynamic ? "dynamically registered" : "approved by a person"}</dd>

          <dt class="opacity-60">Auth method</dt>
          <dd class="col-span-2 font-mono text-xs">{client.tokenEndpointAuthMethod}</dd>

          <dt class="opacity-60">Approved by</dt>
          <dd class="col-span-2">{client.approvedBy?.nickname ?? "—"}</dd>

          <dt class="opacity-60">Resources</dt>
          <dd class="col-span-2 font-mono text-xs break-all">{client.resources.join(" ") || "—"}</dd>

          <dt class="opacity-60">Redirect URIs</dt>
          <dd class="col-span-2 font-mono text-xs break-all">{client.redirectUris.join(" ")}</dd>

          <dt class="opacity-60">Grants</dt>
          <dd class="col-span-2 font-mono text-xs">{client.grantTypes.join(" ")}</dd>
        </dl>

        <div class="flex gap-2 pt-2">
          {#if client.tokenEndpointAuthMethod !== "none"}
            <button class="btn btn-sm" onclick={rotate}>Rotate secret</button>
          {/if}
          {#if !client.archivedAt}
            <button class="btn btn-sm btn-error btn-outline" onclick={archive}>Archive</button>
          {/if}
        </div>
      </div>
    </section>

    <div class="flex flex-col gap-4">
      <section class="card bg-base-100">
        <div class="card-body gap-3">
          <h2 class="card-title text-base">Required scopes</h2>
          <p class="text-xs opacity-70">
            Granted whether or not the client asks for them.
          </p>

          <ScopesEditor
            value={client.requiredScopes}
            available={supported}
            onchange={(requiredScopes) => update({ requiredScopes }, "Required scopes updated.")}
          />
        </div>
      </section>

      <section class="card bg-base-100">
        <div class="card-body gap-3">
          <h2 class="card-title text-base">Allowed scopes</h2>
          <p class="text-xs opacity-70">
            Grantable on request. Their union with the required set is the ceiling this client is
            refused outside.
          </p>

          <ScopesEditor
            value={client.allowedScopes}
            available={supported}
            onchange={(allowedScopes) => update({ allowedScopes }, "Allowed scopes updated.")}
          />

          {#if client.dynamic}
            <p class="text-xs opacity-60">
              Nobody approved this client, so it may not hold a
              <span class="font-mono">masks:</span> scope.
            </p>
          {/if}
        </div>
      </section>
    </div>
  </div>
{/if}
