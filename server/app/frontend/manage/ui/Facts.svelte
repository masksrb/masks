<script>
  import { NONE } from "../lib/format.js";

  let { rows } = $props();
</script>

<dl class="grid grid-cols-3 gap-x-4 gap-y-2 text-sm">
  {#each rows as { term, value, mono } (term)}
    <dt class="opacity-60">{term}</dt>
    <dd class="col-span-2 {mono ? 'font-mono text-xs break-all' : ''}">{value || NONE}</dd>
  {/each}
</dl>
