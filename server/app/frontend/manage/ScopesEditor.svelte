<script>
  let { value = [], available = [], onchange, disabled = false } = $props();

  let adding = $state("");

  const known = $derived([...new Set([...available, ...value])].sort());

  function toggle(scope) {
    onchange(value.includes(scope) ? value.filter((one) => one !== scope) : [...value, scope]);
  }

  function add() {
    const scope = adding.trim();

    if (scope && !value.includes(scope)) onchange([...value, scope]);

    adding = "";
  }
</script>

<div class="flex flex-col gap-3">
  {#if known.length}
    <div class="flex flex-wrap gap-2">
      {#each known as scope (scope)}
        {@const held = value.includes(scope)}
        <button
          type="button"
          class="badge badge-lg font-mono text-xs {held
            ? 'badge-primary'
            : 'badge-ghost opacity-60'} disabled:opacity-40"
          aria-pressed={held}
          {disabled}
          onclick={() => toggle(scope)}
        >{scope}</button>
      {/each}
    </div>
  {/if}

  {#if !disabled}
    <div class="join">
      <input
        class="input input-sm join-item font-mono"
        placeholder="add a scope"
        autocapitalize="none"
        autocorrect="off"
        spellcheck="false"
        bind:value={adding}
        onkeydown={(event) => event.key === "Enter" && add()}
      />
      <button type="button" class="btn btn-sm join-item" onclick={add}>Add</button>
    </div>
  {/if}
</div>
