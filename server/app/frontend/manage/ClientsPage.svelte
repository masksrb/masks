<script>
  import { NONE, day, joined } from "./lib/format.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Row from "./ui/Row.svelte";
  import Search from "./ui/Search.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Switch from "./ui/Switch.svelte";
  import Table from "./ui/Table.svelte";

  let { api } = $props();

  const PAGE = 50;

  const QUERY = `
    query Clients($search: String, $archived: Boolean, $afterId: ID, $limit: Int) {
      clients(search: $search, archived: $archived, afterId: $afterId, limit: $limit) {
        clientId name dynamic approvedAt archivedAt
        requiredScopes allowedScopes resources createdAt
        approvedBy { nickname }
        namespaces { name }
      }
    }
  `;

  const COLUMNS = [
    "Name",
    { label: "Resources", hide: true },
    "Source",
    { label: "Namespaces", hide: true, right: true },
    { label: "Scopes", hide: true },
    { label: "Approved by", hide: true },
    "Created",
  ];

  const feedback = createFeedback();

  let search = $state("");
  let query = $state("");
  let archived = $state(false);
  let clients = $state([]);
  let loading = $state(true);
  let more = $state(false);
  let exhausted = $state(false);

  async function load(afterId = null) {
    if (afterId) more = true;
    else loading = true;

    const data = await feedback.attempt(() =>
      api.query(QUERY, {
        search: query || null,
        archived,
        afterId,
        limit: PAGE,
      }),
    );

    loading = false;
    more = false;

    if (!data) return;

    clients = afterId ? [...clients, ...data.clients] : data.clients;
    exhausted = data.clients.length < PAGE;
  }

  load();

  function again() {
    exhausted = false;
    load();
  }

  function look() {
    query = search;
    again();
  }

  function toggle(held) {
    archived = held;
    again();
  }

  const oldest = $derived(clients.at(-1)?.clientId ?? null);

  const nothing = $derived(
    query
      ? `No ${archived ? "archived " : ""}client matches “${query}”.`
      : archived
        ? "Nothing has been archived."
        : "No applications are registered yet. One appears here as soon as it completes a handshake.",
  );
</script>

<Page title="Clients">
  {#snippet actions()}
    <Switch bind:checked={archived} label="Archived" onchange={toggle} />
    <Search
      bind:value={search}
      label="Search clients"
      placeholder="name or client_id"
      onsearch={look}
    />
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if loading && clients.length === 0}
    <Spinner />
  {:else}
    <Table columns={COLUMNS} count={clients.length} empty={nothing}>
      {#snippet rows()}
        {#each clients as client (client.clientId)}
          <Row to={`/clients/${client.clientId}`}>
            <td class="max-w-[15rem]">
              <Link to={`/clients/${client.clientId}`} class="link link-hover font-medium">
                {client.name}
              </Link>
              <div class="truncate font-mono text-xs opacity-50" title={client.clientId}>
                {client.clientId}
              </div>
            </td>
            <td class="hidden max-w-[16rem] md:table-cell">
              <div class="truncate font-mono text-xs opacity-70" title={joined(client.resources)}>
                {joined(client.resources)}
              </div>
            </td>
            <td>
              {#if client.dynamic}
                <span class="badge badge-ghost badge-sm">self-registered</span>
              {:else}
                <span class="badge badge-success badge-sm">approved</span>
              {/if}
            </td>
            <td class="hidden text-right text-xs opacity-70 md:table-cell">
              {client.namespaces.length || NONE}
            </td>
            <td class="hidden max-w-64 font-mono text-xs md:table-cell">
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
            <td class="hidden text-xs opacity-70 md:table-cell">
              {client.approvedBy?.nickname ?? NONE}
            </td>
            <td class="text-xs whitespace-nowrap opacity-70">{day(client.createdAt)}</td>
          </Row>
        {/each}
      {/snippet}
    </Table>

    {#if !exhausted && clients.length}
      <div>
        <button
          type="button"
          class="btn btn-ghost btn-sm"
          disabled={more}
          onclick={() => load(oldest)}
        >
          {more ? "Loading..." : "Show more"}
        </button>
      </div>
    {/if}
  {/if}
</Page>
