<script>
  import { route, goto } from "@mateothegreat/svelte5-router";

  let { component, ...props } = $props();
  let preferredTab = $state(
    props.useHash ? window.location.hash?.slice(1) || props.tab : props.tab
  );

  let tab = $state(
    preferredTab && props.tabs[preferredTab]
      ? preferredTab
      : Object.keys(preferredTab)[0]
  );

  let changeTab = (key) => {
    return (e) => {
      e.preventDefault();
      e.stopPropagation();

      if (props.tabs[key].disabled) {
        return;
      }

      tab = key;

      if (props.goto && props.tabs[key]?.href) {
        goto(props.tabs[key].href);
      }

      if (props.onchange) {
        props.onchange(props.tabs[tab]);
      }
    };
  };
</script>

<div>
  {#if props?.style == "cards"}
    <div class="w-full mb-1.5">
      <div class="cols-1.5">
        {#each Object.entries(props.tabs) as [key, data]}
          {@const count = props.stats
            ? props.stats[data.statsKey || key]
            : null}
          {@const Icon = data.icon}
          <a
            onclick={changeTab(key)}
            href={data.href}
            disabled={data.disabled ||
              (props.stats && count == 0) ||
              tab == key}
            class={[
              tab == key
                ? `${data.active || "btn-neutral"}`
                : count == 0
                  ? "btn-disabled"
                  : "",
              "btn btn-sm px-3 overflow-hidden w-auto",
            ].join(" ")}
          >
            <span class="cols-1.5">
              <span class="w-4 text-center flex flex-col items-end label-xs">
                <Icon size="14" />
              </span>

              <span class={["hidden md:block label-sm truncate"].join(" ")}>
                {data.name || data.plural}
              </span>

              {#if props.stats}
                <span
                  class={[
                    count > 0 ? "" : "opacity-75",
                    "badge badge-xs text-[9px] text-center badge-outline",
                  ].join(" ")}
                >
                  {count || "–"}
                </span>
              {/if}
            </span>
          </a>
        {/each}
      </div>
    </div>

    <div class="box bg-neutral p-3 md:px-4">
      {#if props.tabs[tab]?.component}
        {@const Tab = props.tabs[tab].component}

        {#if !component}
          <Tab {...props.props} />
        {:else}
          {@render component(Tab)}
        {/if}
      {/if}
    </div>
  {:else}
    <div class="w-full">
      <div class="md:flex">
        <div
          class="flex md:flex-col gap-1.5 rounded-t-box md:rounded-r md:rounded-l-box bg-base-100 pl-1.5 py-1.5"
        >
          {#each Object.entries(props.tabs) as [key, data]}
            {@const count = props.stats
              ? props.stats[data.statsKey || key]
              : null}
            {@const Icon = data.icon}
            <a
              onclick={changeTab(key)}
              href={data.href}
              disabled={data.disabled ||
                (props.stats && count == 0) ||
                tab == key}
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
            {@const extras = props.tabs[tab].props || {}}

            {#if !component}
              <Tab {...props.props} {...extras} />
            {:else}
              {@render component(Tab)}
            {/if}
          {/if}
        </div>
      </div>
    </div>
  {/if}
</div>
