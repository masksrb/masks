<script>
  import {
    LogIn,
    User,
    Handshake,
    MonitorSmartphone,
    Mail,
    Phone,
  } from "lucide-svelte";
  import { route, goto } from "@mateothegreat/svelte5-router";
  import Page from "./Page.svelte";
  import Time from "@/components/Time.svelte";
  import { queryStore, gql, getContextClient } from "@urql/svelte";

  let { component, ...props } = $props();
  let tab = $state(
    props.tab && props.tabs[props.tab] ? props.tab : Object.keys(props.tabs)[0]
  );
  let changeTab = (key) => {
    return (e) => {
      e.preventDefault();
      e.stopPropagation();

      if (!props.goto || !props.tabs[key].href) {
        tab = key;

        if (props.onchange) {
          props.onchange(props.tabs[tab]);
        }
      } else {
        goto(props.tabs[key].href);
      }
    };
  };

  if (props.onchange) {
    props.onchange(props.tabs[tab]);
  }
</script>

<div class="w-full">
  <div class="md:flex">
    <div
      class="flex md:flex-col gap-1.5 rounded-t-box md:rounded-r md:rounded-l-box bg-base-100 pl-1.5 py-1.5"
    >
      {#each Object.entries(props.tabs) as [key, data]}
        {@const count = props.stats ? props.stats[key] : null}
        {@const Icon = data.icon}
        <a
          onclick={changeTab(key)}
          href={data.href}
          disabled={(props.stats && count == 0) || tab == key}
          class={[
            tab == key ? "btn-neutral" : count == 0 ? "btn-disabled" : "",
            "flex items-center justify-start gap-1.5 flex-nowrap whitespace-nowrap btn btn-sm",
            "md:rounded-r-none px-1.5 pr-2.5",
          ].join(" ")}
        >
          <div class="w-4 text-center flex flex-col items-end">
            <Icon size="14" />
          </div>

          {#if props.name}
            <span class={["hidden md:block font-normal"].join(" ")}>
              {data.name}
            </span>
          {/if}

          {#if props.stats}
            <span
              class={[
                tab == key ? "badge-info" : "badge-neutral",
                count > 0 ? "" : "opacity-75",
                "badge badge-xs text-[9px] text-center",
              ].join(" ")}
            >
              {count || "–"}
            </span>
          {/if}
        </a>
      {/each}
    </div>

    <div
      class="grow bg-neutral rounded-b-box md:rounded-l md:rounded-r-box p-3 overflow-hidden"
    >
      {#if props.tabs[tab]?.component}
        {@const Tab = props.tabs[tab].component}

        {#if !component}
          <Tab {...props.props} />
        {:else}
          {@render component(Tab)}
        {/if}
      {/if}
    </div>
  </div>
</div>
