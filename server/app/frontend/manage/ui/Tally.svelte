<script>
  import Link from "./Link.svelte";

  let { counts } = $props();
</script>

<div class="tally">
  {#each counts as count (count.label)}
    {#if count.to}
      <Link to={count.to} class="tally-cell">
        <span class="tally-figure">{count.value}</span>
        <span class="tally-label">{count.label}</span>
      </Link>
    {:else}
      <div class="tally-cell">
        <span class="tally-figure">{count.value}</span>
        <span class="tally-label">{count.label}</span>
      </div>
    {/if}
  {/each}
</div>
