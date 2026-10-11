<script>
  import { t } from "../lib/copy.js";
  let { pages, shown, busy = false, onpage } = $props();

  const first = $derived(pages.first);
  const last = $derived(first + shown - 1);
  const total = $derived(pages.state.total);
  const earlier = $derived(pages.state.cursors.length > 1);
  const later = $derived(total === null ? shown === pages.size : last < total);
</script>

{#if shown && (earlier || later)}
  <nav class="pager" aria-label={t("ui.pager.label")}>
    <span class="hint">
      {total === null
        ? t("ui.pager.range", { first: first.toLocaleString(), last: last.toLocaleString() })
        : t("ui.pager.range_of", {
            first: first.toLocaleString(),
            last: last.toLocaleString(),
            total: total.toLocaleString(),
          })}
    </span>

    <div class="join">
      <button
        type="button"
        class="btn btn-sm join-item"
        disabled={busy || !earlier}
        onclick={() => onpage("back")}
      >{t("ui.pager.previous")}</button>
      <button
        type="button"
        class="btn btn-sm join-item"
        disabled={busy || !later}
        onclick={() => onpage("forward")}
      >{t("ui.pager.next")}</button>
    </div>
  </nav>
{/if}
