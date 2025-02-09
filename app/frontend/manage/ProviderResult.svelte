<script>
  import _ from "lodash-es";
  import Icon from "@iconify/svelte";
  import Time from "@/components/Time.svelte";
  import CopyText from "@/components/CopyText.svelte";
  import { ChevronRight, Trash2, Settings2, X, Github } from "lucide-svelte";
  import { iconifyProvider } from "@/lib";
  import { getContext } from "svelte";

  let { provider, settings, change, ...props } = $props();

  let { root } = getContext("page");
</script>

{#if provider}
  <div class="bg-base-100 px-3 pt-1 pb-1 rounded-lg">
    <div class="flex items-center gap-3">
      <div
        class="bg-base-100 rounded-lg p-[4px] min-w-[30px] w-[30px] h-[30px] fill-white shadow-inner"
      >
        <Icon icon={iconifyProvider(provider)} width="100%" height="100%" />
      </div>

      <div class="grow">
        {#if props.link}
          <a href={`${root}/sso/${provider.id}`} class="text-sm font-bold"
            >{provider.name}</a
          >
        {:else}
          <input
            type="text"
            value={provider.name}
            oninput={(e) => change({ name: e.target.value })}
            class="text-sm font-bold bg-transparent !outline-none w-full"
            disabled={!change}
          />
        {/if}
      </div>

      <div class="flex flex-col items-end mr-1.5">
        <span class="label-xs truncate"
          ><Time timestamp={provider.createdAt} ago="old" /></span
        >
        {#if provider.disabled}
          <b class="text-xs truncate text-warning">disabled</b>
        {:else if !provider.setup}
          <b class="text-xs truncate text-info">setup required</b>
        {:else}
          <b class="text-xs truncate text-success">active</b>
        {/if}
      </div>

      {#if props.link}
        <a
          href={`${root}/sso/${provider.id}`}
          class="btn btn-xs btn-square btn-icon"
        >
          <ChevronRight size="18" />
        </a>
      {/if}
    </div>
  </div>
{/if}
