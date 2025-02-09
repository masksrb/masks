<script>
  import { TokenFragment, PageInfoFragment } from "@/util.js";
  import { route } from "@mateothegreat/svelte5-router";
  import {
    Trash2 as Trash,
    Search,
    ChevronDown,
    ChevronRight,
  } from "lucide-svelte";
  import Time from "@/components/Time.svelte";
  import Identicon from "@/components/Identicon.svelte";
  import EditableImage from "@/components/EditableImage.svelte";
  import DeviceIcon from "@/components/DeviceIcon.svelte";
  import { queryStore, gql, getContextClient } from "@urql/svelte";
  import QuerySearch from "@/components/QuerySearch.svelte";
  import PaginateSearch from "@/components/PaginateSearch.svelte";
  import TokenResult from "../TokenResult.svelte";
  import Query from "@/components/Query.svelte";

  let props = $props();
  let query = gql`
    query (
      $after: String
      $before: String
      $id: String
      $actor: String
      $client: String
      $device: String
    ) {
      tokens(
        after: $after
        before: $before
        id: $id
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

  let device = (token) => {
    return props.device || token.device;
  };
</script>

<Query {query} key="tokens" {...props}>
  {#snippet children({ refresh, result, loading })}
    {#if !props.result}
      <PaginateSearch
        label="Tokens"
        class="mb-3"
        {result}
        {refresh}
        {loading}
      />

      {#if !props.variables}
        <QuerySearch
          url="/manage/tokens"
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
      {/each}
    </div>
  {/snippet}
</Query>
