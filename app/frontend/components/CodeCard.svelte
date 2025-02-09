<script>
  import { Save, ChevronDown, X } from "lucide-svelte";
  import Time from "svelte-time";

  let { code } = $props();

  let form = { ...code };
</script>

<div class="my-1.5 bg-base-200 rounded-lg p-3 px-3">
  <div class="flex items-center pl-1.5 gap-3">
    <h2 class="font-bold font-mono">{code.code}</h2>
    {#if code.nonce}
      <h2 class="opacity-70 font-xs">{code.nonce}</h2>
    {/if}
    <div class="grow"></div>
    <span class="opacity-70">created</span>
    <span class="italic"><Time relative timestamp={code.createdAt} /></span>
    <span class="opacity-70">expiry</span>
    <span class="italic"><Time relative timestamp={code.expiresAt} /></span>
  </div>
</div>
