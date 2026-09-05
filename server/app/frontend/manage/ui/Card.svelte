<script>
  let { title = null, lede = null, actions, children } = $props();
</script>

<section class="card border border-base-300 bg-base-100">
  <div class="card-body gap-4">
    {#if title || lede || actions}
      <div class="flex flex-wrap items-start justify-between gap-x-4 gap-y-2">
        <div class="flex min-w-0 flex-col gap-1.5">
          {#if title}<h2 class="subhead">{title}</h2>{/if}
          {#if lede}<p class="deck-sm">{lede}</p>{/if}
        </div>

        {#if actions}
          <div class="flex flex-none items-center gap-2">{@render actions()}</div>
        {/if}
      </div>
    {/if}

    {@render children()}
  </div>
</section>
