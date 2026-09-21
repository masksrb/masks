<script>
  import { initial } from "../../lib/initial.js";

  let { client, class: sized = "size-8 rounded" } = $props();
</script>

{#if client.logoUrl}
  <img src={client.logoUrl} alt="" class="shrink-0 {sized}" />
{:else}
  <span class="grid shrink-0 place-items-center bg-base-200 font-semibold {sized}" aria-hidden="true"
    >{initial(client.name)}</span
  >
{/if}
