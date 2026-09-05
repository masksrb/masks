<script>
  import { joined } from "./lib/format.js";
  import Link from "./ui/Link.svelte";
  import Loader from "./ui/Loader.svelte";
  import Page from "./ui/Page.svelte";
  import Row from "./ui/Row.svelte";
  import Search from "./ui/Search.svelte";
  import Switch from "./ui/Switch.svelte";
  import Table from "./ui/Table.svelte";

  let { api } = $props();

  const QUERY = `
    query Clients($search: String, $archived: Boolean) {
      clients(search: $search, archived: $archived) {
        clientId name dynamic approvedAt archivedAt tokenEndpointAuthMethod
        requiredScopes allowedScopes resources createdAt
        approvedBy { nickname }
      }
    }
  `;

  const COLUMNS = ["Name", "Resources", "How it got here", "Scopes", "Approved by"];

  let search = $state("");
  let query = $state("");
  let archived = $state(false);

  const stamp = $derived(`${query}:${archived}`);

  const nothing = $derived(
    query
      ? `No ${archived ? "archived " : ""}client matches “${query}”.`
      : archived
        ? "Nothing has been archived."
        : "No applications are registered yet. One appears here as soon as it completes a handshake.",
  );
</script>

<Page
  title="Clients"
  lede="Applications registered against this server. A client may never be granted more than its scopes allow."
>
  {#snippet actions()}
    <Switch bind:checked={archived} label="Archived" />
    <Search
      bind:value={search}
      label="Search clients"
      placeholder="name or client_id"
      onsearch={() => (query = search)}
    />
  {/snippet}

  {#key stamp}
    <Loader load={() => api.query(QUERY, { search: query || null, archived })}>
      {#snippet children(data)}
        <Table columns={COLUMNS} count={data.clients.length} empty={nothing}>
          {#snippet rows()}
            {#each data.clients as client (client.clientId)}
              <Row to={`/clients/${client.clientId}`}>
                <td>
                  <Link to={`/clients/${client.clientId}`} class="link link-hover font-medium">
                    {client.name}
                  </Link>
                  <div class="font-mono text-xs opacity-50">{client.clientId}</div>
                </td>
                <td class="font-mono text-xs opacity-70">{joined(client.resources)}</td>
                <td>
                  <div class="flex flex-col items-start gap-1">
                    {#if client.dynamic}
                      <span class="badge badge-ghost badge-sm">self-registered</span>
                    {:else}
                      <span class="badge badge-success badge-sm">approved</span>
                    {/if}
                    {#if client.tokenEndpointAuthMethod === "none"}
                      <span class="badge badge-outline badge-xs">secretless</span>
                    {/if}
                  </div>
                </td>
                <td class="max-w-64 font-mono text-xs">
                  {#if client.requiredScopes.length}
                    <div class="truncate" title={joined(client.requiredScopes)}>
                      <span class="opacity-50">always</span>
                      {joined(client.requiredScopes)}
                    </div>
                  {/if}
                  {#if client.allowedScopes.length}
                    <div class="truncate opacity-70" title={joined(client.allowedScopes)}>
                      <span class="opacity-70">on request</span>
                      {joined(client.allowedScopes)}
                    </div>
                  {/if}
                </td>
                <td class="text-xs opacity-70">{client.approvedBy?.nickname ?? "—"}</td>
              </Row>
            {/each}
          {/snippet}
        </Table>
      {/snippet}
    </Loader>
  {/key}
</Page>
