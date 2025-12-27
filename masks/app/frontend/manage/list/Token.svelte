<script>
import { TokenFragment, PageInfoFragment } from "@/lib";
import { gql } from "@urql/svelte";
import QuerySearch from "@/components/QuerySearch.svelte";
import PaginateSearch from "@/components/PaginateSearch.svelte";
import TokenResult from "../TokenResult.svelte";
import Query from "@/components/Query.svelte";
import { getContext } from "svelte";

let props = $props();
let { root } = getContext("page");
let query = gql`
    query (
      $after: String
      $before: String
      $id: String
      $name: String
      $actor: String
      $client: String
      $device: String
    ) {
      tokens(
        after: $after
        before: $before
        id: $id
        name: $name
        actor: $actor
        client: $client
        device: $device
      ) {
        pageInfo {
          ...PageInfoFragment
        }
        nodes {
          ...TokenFragment
        }
      }
    }

    ${TokenFragment}
    ${PageInfoFragment}
  `;
</script>

<Query {query} key="tokens" {...props}>
  {#snippet children({ refresh, result, loading })}
    {#if !props.result}
      <PaginateSearch
        url={`${root}/tokens`}
        label="Tokens"
        class="mb-3"
        {result}
        {refresh}
        {loading}
      />

      {#if !props.variables}
        <QuerySearch
          url={`${root}/tokens`}
          keys={["id", "name", "actor", "client", "device"]}
          class="mb-3"
          onquery={refresh}
          empty={result?.length == 0}
          editable={!props.variables}
          {loading}
        />
      {/if}
    {/if}

    <div class="flex flex-col gap-1.5">
      {#each props.result || result.nodes as token}
        <TokenResult {token} {...props} />
      {:else}
        {#if !loading}
          <div
            class="box border border-base-100 border-dashed border-opacity-50"
          >
            <span class="label-sm text-neutral-content">Nothing found...</span>
          </div>
        {/if}
      {/each}
    </div>
  {/snippet}
</Query>
