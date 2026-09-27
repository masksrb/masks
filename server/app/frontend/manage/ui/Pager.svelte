<script>
  let { pages, shown, busy = false, onpage } = $props();

  const first = $derived(pages.first);
  const last = $derived(first + shown - 1);
  const total = $derived(pages.state.total);
  const earlier = $derived(pages.state.cursors.length > 1);
  const later = $derived(total === null ? shown === pages.size : last < total);
</script>

{#if shown && (earlier || later)}
  <nav class="pager" aria-label="Pages">
    <span class="hint">
      {first.toLocaleString()}–{last.toLocaleString()}{total === null ? "" : ` of ${total.toLocaleString()}`}
    </span>

    <div class="join">
      <button
        type="button"
        class="btn btn-sm join-item"
        disabled={busy || !earlier}
        onclick={() => onpage("back")}
      >Previous</button>
      <button
        type="button"
        class="btn btn-sm join-item"
        disabled={busy || !later}
        onclick={() => onpage("forward")}
      >Next</button>
    </div>
  </nav>
{/if}
