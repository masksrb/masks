<script>
  import { NONE } from "../lib/format.js";

  let { rows } = $props();
</script>

<dl class="grid gap-x-4 gap-y-0.5 text-sm sm:grid-cols-3 sm:gap-y-2">
  {#each rows as { term, value, mono } (term)}
    <dt class="opacity-60">{term}</dt>
    <dd class="pb-2 sm:col-span-2 sm:pb-0 {mono ? 'font-mono text-xs break-all' : ''}">
      {value || NONE}
    </dd>
  {/each}
</dl>
