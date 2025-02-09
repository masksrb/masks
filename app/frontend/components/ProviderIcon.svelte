<script>
  import Icon from "@iconify/svelte";
  import { iconifyProvider } from "@/util.js";

  let { provider, ...props } = $props();
</script>

{#if props.bg}
  <div class={`rounded-lg ${props.class}`}>
    <Icon icon={iconifyProvider(provider)} width="100%" height="100%" />
  </div>
{:else}
  <Icon icon={iconifyProvider(provider)} />
{/if}
