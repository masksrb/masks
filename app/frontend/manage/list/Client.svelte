<script>
  import { PageInfoFragment } from "@/util.js";
  import Time from "@/components/Time.svelte";
  import EditableImage from "@/components/EditableImage.svelte";
  import QuerySearch from "@/components/QuerySearch.svelte";
  import PaginateSearch from "@/components/PaginateSearch.svelte";
  import { queryStore, gql, getContextClient } from "@urql/svelte";
  import Query from "@/components/Query.svelte";

  let { ...props } = $props();
  let query = gql`
    query (
      $after: String
      $before: String
      $name: String
      $actor: String
      $device: String
    ) {
      clients(
        after: $after
        before: $before
        name: $name
        actor: $actor
        device: $device
      ) {
        pageInfo {
          ...PageInfoFragment
        }

        nodes {
          id
          name
          logo
          createdAt
        }
      }
    }

    ${PageInfoFragment}
  `;
</script>

<Query {query} key="clients" {...props}>
  {#snippet children({ refresh, result, loading })}
    {#if !props.result}
      <PaginateSearch
        label="Clients"
        class="mb-3"
        count={result?.length}
        {result}
        {refresh}
        {loading}
      />

      {#if !props.variables}
        <QuerySearch
          url="/manage/clients"
          keys={["name", "actor", "device"]}
          class="mb-3"
          onquery={refresh}
          empty={result?.length == 0}
          editable={!props.variables}
          {loading}
        />
      {/if}
    {/if}

    {#each result.nodes as client}
      <a href={`/manage/client/${client.id}`} class="mb-1.5">
        <div class="bg-base-100 rounded-lg p-1.5 text-base-content">
          <div class="flex items-center gap-2">
            <EditableImage
              disabled
              params={{ client_id: client.id }}
              src={client.logo}
              class="w-8 h-8"
            />

            <div class="grow">
              <div class="font-bold text-xs">
                {client.name}
              </div>
              <div class="font-mono text-xs flex items-center gap-1.5">
                <span class="opacity-75">id</span>
                {client.id}
              </div>
            </div>

            <div class="text-xs font-normal opacity-75 truncate pr-1.5">
              <Time relative timestamp={client.createdAt} ago="old" />
            </div>
          </div>
        </div>
      </a>
    {/each}
  {/snippet}
</Query>
