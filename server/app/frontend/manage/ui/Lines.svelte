<script>
  let { label, hint = null, value = [], onsave, save = "Save", rows = 3 } = $props();

  let draft = $state(value.join("\n"));
  let held = $state(value.join("\n"));

  $effect(() => {
    const fresh = value.join("\n");

    if (fresh === held) return;

    held = fresh;
    draft = fresh;
  });

  const changed = $derived(draft !== held);

  const lines = () =>
    draft
      .split("\n")
      .map((one) => one.trim())
      .filter(Boolean);
</script>

<label class="flex flex-col gap-1.5">
  <span class="text-xs font-medium opacity-70">{label}</span>

  <textarea
    class="textarea textarea-sm w-full font-mono text-xs"
    {rows}
    autocapitalize="none"
    autocorrect="off"
    spellcheck="false"
    bind:value={draft}
  ></textarea>

  {#if hint}
    <span class="text-xs opacity-60">{hint}</span>
  {/if}

  <button
    type="button"
    class="btn btn-sm self-start"
    disabled={!changed}
    onclick={() => onsave(lines())}
  >
    {save}
  </button>
</label>
