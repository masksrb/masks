<script>
  import {
    LogIn,
    User,
    Handshake,
    MonitorSmartphone,
    Mail,
    Phone,
    X,
    AlertTriangle,
  } from "lucide-svelte";
  import { route, goto } from "@mateothegreat/svelte5-router";
  import Page from "./Page.svelte";
  import Time from "@/components/Time.svelte";
  import Alert from "@/components/Alert.svelte";
  import { queryStore, gql, getContextClient } from "@urql/svelte";

  let { record, component, ...props } = $props();
  let tab = $state(props.tab);
  let changeTab = (key) => {
    return (e) => {
      e.preventDefault();
      e.stopPropagation();

      tab = key;
    };
  };

  if (props.onchange) {
    props.onchange(props.tabs[tab]);
  }
</script>

<div class="p-3 py-1.5 rounded-lg bg-black">
  <div class="flex items-center gap-1.5">
    {#each Object.entries(props.tabs) as [key, data]}
      {@const count = record?.stats ? record?.stats[key] : null}
      {@const Icon = data.icon}
      <button
        onclick={changeTab(key)}
        class={[
          "btn btn-xs flex items-center",
          tab == key ? "btn-neutral" : count == 0 ? "btn-disabled" : "",
        ].join(" ")}
      >
        {#if record.stats && count >= 0}
          <span
            class={[
              tab == key ? "badge-info" : "badge-neutral",
              count > 0 ? "" : "opacity-75",
              "badge badge-xs text-[9px] text-center hidden md:block",
            ].join(" ")}
          >
            {count || "–"}
          </span>
        {/if}

        <div
          class={`w-4 text-center flex flex-col items-end ${record.stats && count >= 0 ? "md:hidden" : ""}`}
        >
          <Icon size="14" class={tab == key ? "text-white" : ""} />
        </div>

        <span class="hidden md:block">
          {data.name}
        </span>
      </button>
    {/each}

    {#if record?.updatedAt}
      <div class="text-xs grow"></div>

      <div class="text-xs pr-1.5 whitespace-nowrap">
        <span class="opacity-75">saved</span>

        {#key record.updatedAt}
          <Time timestamp={record.updatedAt} />
        {/key}
      </div>
    {/if}

    {@render props?.after?.()}
  </div>

  {#if props.errors?.length > 0}
    <Alert type="error" class="mt-3">
      <ul class="text-sm list-disc pl-6 flex flex-col gap-1.5">
        {#each props.errors as error}
          <li class="">{error}</li>
        {/each}
      </ul>
    </Alert>
  {/if}

  {#if props.tabs[tab]?.component}
    {@const Tab = props.tabs[tab].component}
    {@const tabProps = props.tabs[tab]?.props || props.props || {}}
    <div class="grow pt-3">
      {#if !component}
        <Tab {...tabProps} />
      {:else}
        {@render component(Tab, tabProps)}
      {/if}
    </div>
  {/if}
</div>
