<script>
  import Loader from "./Loader.svelte";

  let { api, router } = $props();

  let search = $state("");
  let archived = $state(false);
  let token = $state(0);

  const QUERY = `
    query Clients($search: String, $archived: Boolean) {
      clients(search: $search, archived: $archived) {
        clientId name dynamic approvedAt archivedAt tokenEndpointAuthMethod
        requiredScopes allowedScopes resources createdAt
        approvedBy { nickname }
      }
    }
  `;
</script>

<div class="flex items-center gap-3 mb-4">
  <h1 class="text-xl font-bold flex-1">Clients</h1>

  <label class="label cursor-pointer gap-2 text-sm">
    <input type="checkbox" class="toggle toggle-sm" bind:checked={archived} onchange={() => (token += 1)} />
    Archived
  </label>

  <input
    class="input input-sm input-bordered"
    placeholder="name or client_id"
    bind:value={search}
    onkeydown={(e) => e.key === "Enter" && (token += 1)}
  />
</div>

{#key token}
  <Loader load={() => api.query(QUERY, { search: search || null, archived })}>
    {#snippet children(data)}
      <div class="overflow-x-auto bg-base-100 rounded-box">
        <table class="table">
          <thead>
            <tr><th>Name</th><th>Origin</th><th>Kind</th><th>Scopes</th><th>Approved</th></tr>
          </thead>
          <tbody>
            {#each data.clients as client (client.clientId)}
              <tr class="hover cursor-pointer" onclick={() => router.go(`/clients/${client.clientId}`)}>
                <td>
                  <div class="font-medium">{client.name}</div>
                  <div class="font-mono text-xs opacity-50">{client.clientId}</div>
                </td>
                <td class="text-xs font-mono opacity-70">{client.resources.join(" ") || "—"}</td>
                <td class="flex flex-col gap-1 items-start">
                  {#if client.dynamic}
                    <span class="badge badge-ghost badge-sm">dynamic</span>
                  {:else}
                    <span class="badge badge-success badge-sm">approved</span>
                  {/if}
                  {#if client.tokenEndpointAuthMethod === "none"}
                    <span class="badge badge-outline badge-xs">public</span>
                  {/if}
                </td>
                <td class="font-mono text-xs">
                  {#if client.requiredScopes.length}
                    <div><span class="opacity-50">required</span> {client.requiredScopes.join(" ")}</div>
                  {/if}
                  <div class="opacity-70">{client.allowedScopes.join(" ")}</div>
                </td>
                <td class="text-xs opacity-70">
                  {client.approvedBy?.nickname ?? "—"}
                </td>
              </tr>
            {/each}
          </tbody>
        </table>

        {#if data.clients.length === 0}
          <p class="p-6 text-sm opacity-70">No clients match that.</p>
        {/if}
      </div>
    {/snippet}
  </Loader>
{/key}
