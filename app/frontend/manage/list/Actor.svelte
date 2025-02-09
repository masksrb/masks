<script>
  import { PageInfoFragment } from "@/util.js";
  import { route } from "@mateothegreat/svelte5-router";
  import Time from "@/components/Time.svelte";
  import Avatar from "@/components/Avatar.svelte";
  import QuerySearch from "@/components/QuerySearch.svelte";
  import PaginateSearch from "@/components/PaginateSearch.svelte";
  import { queryStore, gql, getContextClient } from "@urql/svelte";
  import Query from "@/components/Query.svelte";

  let props = $props();
  let query = gql`
    query ($identifier: String) {
      actors(identifier: $identifier) {
        pageInfo {
          ...PageInfoFragment
        }

        nodes {
          id
          name
          identifier
          identiconId
          lastLoginAt
          createdAt
        }
      }
    }

    ${PageInfoFragment}
  `;
</script>

<Query {query} key="actors.nodes" {...props}>
  {#snippet children({ refresh, result, loading })}
    {#if !props.result}
      <PaginateSearch
        label="Actors"
        class="mb-3"
        count={result?.length}
        {result}
        {loading}
        {refresh}
      />

      {#if !props.variables}
        <QuerySearch
          url="/manage/actors"
          keys={["identifier"]}
          class="mb-3"
          onquery={refresh}
          empty={result?.length == 0}
          editable={!props.variables}
          {loading}
        />
      {/if}
    {/if}

    {#each result as actor}
      <a
        use:route
        href={`/manage/actor/${actor.id}`}
        class="bg-base-100 rounded-lg p-1.5 block mb-1.5 leading-snug"
      >
        <div class="grow flex items-center gap-3">
          <div class="w-6 h-6">
            <Avatar {actor} />
          </div>

          <p class="font-bold mb-0.5">
            {actor.identifier}
          </p>
          <div class="grow text-xs font-normal opacity-75 truncate">
            <Time relative timestamp={actor.createdAt} ago="old" />
          </div>
          <div class="text-xs font-normal opacity-75 truncate pr-1.5">
            last login

            <span class="italic">
              {#if actor.lastLoginAt}
                <Time relative timestamp={actor.lastLoginAt} />
              {:else}
                never
              {/if}
            </span>
          </div>
        </div>
      </a>
    {/each}
  {/snippet}
</Query>
