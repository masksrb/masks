<script>
import { ProviderFragment, PageInfoFragment } from "@/lib";
import Time from "@/components/Time.svelte";
import EditableImage from "@/components/EditableImage.svelte";
import QuerySearch from "@/components/QuerySearch.svelte";
import PaginateSearch from "@/components/PaginateSearch.svelte";
import { queryStore, gql, getContextClient } from "@urql/svelte";
import Query from "@/components/Query.svelte";
import { getContext } from "svelte";
import ProviderResult from "../ProviderResult.svelte";

let { root } = getContext("page");

let { settings, ...props } = $props();
let query = gql`
    query (
      $after: String
      $before: String
      $name: String
      $type: String
      $id: String
    ) {
      providers(
        after: $after
        before: $before
        name: $name
        type: $type
        id: $id
      ) {
        pageInfo {
          ...PageInfoFragment
        }

        nodes {
          ...ProviderFragment
        }
      }
    }

    ${PageInfoFragment}
    ${ProviderFragment}
  `;
</script>

<Query {query} key="providers" {...props}>
  {#snippet children({ refresh, result, loading })}
    {#if !props.result}
      <PaginateSearch
        label="SSO providers"
        class="mb-3"
        count={result?.length}
        {result}
        {refresh}
        {loading}
      />

      {#if !props.variables}
        <QuerySearch
          url="${root}/sso"
          keys={["name", "type"]}
          class="mb-3"
          onquery={refresh}
          empty={result?.length == 0}
          editable={!props.variables}
          {loading}
        />
      {/if}
    {/if}

    <div class="rows-1.5">
      {#each result.nodes as provider}
        <ProviderResult {settings} {provider} {root} link />
      {/each}
    </div>
  {/snippet}
</Query>
