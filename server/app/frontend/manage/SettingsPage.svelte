<script>
  import ScopesEditor from "./ScopesEditor.svelte";

  let { api, boot, overview = false } = $props();

  const QUERY = `
    query Tenant {
      tenant {
        uuid subdomain name dynamicClientScopes createdAt
        signingKeys { kid algorithm activatedAt retiredAt retired }
      }
      viewer { nickname scopes }
      actors { uuid }
      clients { clientId dynamic }
      sessions { id }
      scopesSupported
    }
  `;

  let data = $state(null);
  let name = $state("");
  let loading = $state(true);
  let notice = $state(null);
  let failure = $state(null);

  async function load() {
    loading = true;

    try {
      data = await api.query(QUERY);
      name = data.tenant.name;
    } catch (thrown) {
      failure = thrown.message;
    } finally {
      loading = false;
    }
  }

  load();

  async function update(changes, message) {
    notice = null;
    failure = null;

    try {
      await api.query(
        `mutation Update($name: String, $dynamicClientScopes: [String!]) {
          updateTenant(name: $name, dynamicClientScopes: $dynamicClientScopes) { tenant { name } }
        }`,
        changes,
      );

      notice = message;
      await load();
    } catch (thrown) {
      failure = thrown.message;
    }
  }
</script>

{#if loading && !data}
  <div class="py-16 grid place-items-center"><span class="loading loading-spinner"></span></div>
{:else if !data}
  <div class="alert alert-error text-sm" role="alert">{failure}</div>
{:else if overview}
  <h1 class="text-xl font-bold mb-1">{data.tenant.name}</h1>
  <p class="text-xs opacity-60 font-mono mb-6">{boot.issuer}</p>

  <div class="stats bg-base-100 w-full mb-6">
    <div class="stat">
      <div class="stat-title">Actors</div>
      <div class="stat-value text-3xl">{data.actors.length}</div>
    </div>
    <div class="stat">
      <div class="stat-title">Clients</div>
      <div class="stat-value text-3xl">{data.clients.length}</div>
      <div class="stat-desc">{data.clients.filter((c) => c.dynamic).length} registered themselves</div>
    </div>
    <div class="stat">
      <div class="stat-title">Live sessions</div>
      <div class="stat-value text-3xl">{data.sessions.length}</div>
    </div>
    <div class="stat">
      <div class="stat-title">Signing keys</div>
      <div class="stat-value text-3xl">{data.signingKeys?.length ?? data.tenant.signingKeys.length}</div>
    </div>
  </div>

  <div class="card bg-base-100">
    <div class="card-body gap-2">
      <h2 class="card-title text-base">You are signed in as {data.viewer.nickname}</h2>
      <p class="text-sm opacity-70">
        This page holds a bearer token issued for
        <span class="font-mono text-xs">{boot.resource}</span>, carrying
        <span class="font-mono text-xs">{data.viewer.scopes.join(" ")}</span>. Revoking it ends
        administration without ending the sign-in.
      </p>
    </div>
  </div>
{:else}
  <h1 class="text-xl font-bold mb-4">Settings</h1>

  {#if notice}<div class="alert alert-success text-sm mb-4">{notice}</div>{/if}
  {#if failure}<div class="alert alert-error text-sm mb-4" role="alert">{failure}</div>{/if}

  <div class="grid md:grid-cols-2 gap-4 items-start">
    <section class="card bg-base-100">
      <div class="card-body gap-3">
        <h2 class="card-title text-base">Tenant</h2>

        <label class="form-control">
          <span class="label-text text-xs opacity-70">Name</span>
          <div class="join">
            <input class="input input-sm input-bordered join-item w-full" bind:value={name} />
            <button class="btn btn-sm join-item" onclick={() => update({ name }, "Renamed.")}>Save</button>
          </div>
        </label>

        <dl class="text-sm grid grid-cols-3 gap-y-2">
          <dt class="opacity-60">Subdomain</dt>
          <dd class="col-span-2 font-mono text-xs">{data.tenant.subdomain}</dd>

          <dt class="opacity-60">Issuer</dt>
          <dd class="col-span-2 font-mono text-xs break-all">{boot.issuer}</dd>

          <dt class="opacity-60">Resource</dt>
          <dd class="col-span-2 font-mono text-xs break-all">{boot.resource}</dd>
        </dl>
      </div>
    </section>

    <div class="flex flex-col gap-4">
      <section class="card bg-base-100">
        <div class="card-body gap-3">
          <h2 class="card-title text-base">Open registration ceiling</h2>
          <p class="text-xs opacity-70">
            The most a client registering itself may ask for. Leave it empty and anything outside the
            <span class="font-mono">masks:</span> namespace is grantable.
          </p>

          <ScopesEditor
            value={data.tenant.dynamicClientScopes ?? []}
            available={data.scopesSupported}
            onchange={(dynamicClientScopes) => update({ dynamicClientScopes }, "Ceiling updated.")}
          />
        </div>
      </section>

      <section class="card bg-base-100">
        <div class="card-body gap-3">
          <h2 class="card-title text-base">Signing keys</h2>

          <table class="table table-sm">
            <thead><tr><th>kid</th><th>Algorithm</th><th>State</th></tr></thead>
            <tbody>
              {#each data.tenant.signingKeys as key (key.kid)}
                <tr>
                  <td class="font-mono text-xs">{key.kid.slice(0, 8)}</td>
                  <td class="text-xs">{key.algorithm}</td>
                  <td>
                    {#if key.retired}
                      <span class="badge badge-ghost badge-sm">retired</span>
                    {:else if key.activatedAt}
                      <span class="badge badge-success badge-sm">active</span>
                    {:else}
                      <span class="badge badge-warning badge-sm">staged</span>
                    {/if}
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  </div>
{/if}
