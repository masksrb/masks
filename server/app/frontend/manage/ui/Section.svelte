<script>
  import Tip from "./Tip.svelte";

  let { title = null, lede = null, help = null, row = false, actions, children } = $props();
</script>

<section class="section" class:section-row={row}>
  {#if title || lede || actions}
    <div class="section-head">
      <div class="flex min-w-0 flex-col gap-1.5">
        {#if title}
          <div class="flex items-center gap-2">
            <h2 class="subhead">{title}</h2>
            {#if help}<Tip text={help} label="About {title.toLowerCase()}" />{/if}
          </div>
        {/if}
        {#if lede}<p class="deck-sm">{lede}</p>{/if}
      </div>

      {#if actions}
        <div class="flex flex-none flex-wrap items-center gap-2">{@render actions()}</div>
      {/if}
    </div>
  {/if}

  <div class="section-body">{@render children()}</div>
</section>
