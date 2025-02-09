<script>
  import {
    Save,
    ChevronDown,
    X,
    Computer,
    Smartphone,
    Tablet,
    Gamepad,
    Tv,
    Tv2,
    HelpCircle,
    Car,
    Camera,
    Bluetooth,
  } from "lucide-svelte";
  import { route } from "@mateothegreat/svelte5-router";
  import Time from "@/components/Time.svelte";
  import EditableImage from "@/components/EditableImage.svelte";
  import DeviceIcon from "@/components/DeviceIcon.svelte";
  import QuerySearch from "@/components/QuerySearch.svelte";
  import PaginateSearch from "@/components/PaginateSearch.svelte";
  import { PageInfoFragment } from "@/util.js";
  import { queryStore, gql, getContextClient } from "@urql/svelte";
  import Query from "@/components/Query.svelte";

  let props = $props();
  let query = gql`
    query ($after: String, $before: String, $id: String, $actor: String) {
      devices(after: $after, before: $before, id: $id, actor: $actor) {
        pageInfo {
          ...PageInfoFragment
        }

        nodes {
          id
          name
          type
          ip
          os
          userAgent
          createdAt
        }
      }
    }

    ${PageInfoFragment}
  `;
</script>

<Query {query} key="devices" {...props}>
  {#snippet children({ refresh, result, loading })}
    {#if !props.devices}
      <PaginateSearch
        label="Devices"
        class="mb-3"
        count={result?.length}
        {result}
        {refresh}
        {loading}
      />

      <QuerySearch
        url="/manage/devices"
        keys={["id", "actor"]}
        class="mb-3"
        onquery={refresh}
        empty={result?.length == 0}
        editable={!props.variables}
        {loading}
      />
    {/if}

    {#each result.nodes as device}
      <a use:route href={`/manage/device/${device.id}`}>
        <span class={"block mb-1.5 bg-base-100 rounded-lg p-3 py-1.5"}>
          <span class="flex items-center gap-3 text-sm w-full">
            <span class="px-1.5">
              <DeviceIcon {device} size="14" />
            </span>

            <span class="whitespace-nowrap font-bold" alt={device.userAgent}
              >{device.name} on {device.os}</span
            >
            <span class="text-xs font-mono grow">{device.ip}</span>

            <span
              class="text-[10px] font-mono opacity-75
              truncate"
            >
              {device.id}
            </span>

            <span class="whitespace-nowrap text-xs opacity-75"
              ><Time relative timestamp={device.createdAt} ago="old" /></span
            >
          </span>
        </span>
      </a>
    {/each}
  {/snippet}
</Query>
