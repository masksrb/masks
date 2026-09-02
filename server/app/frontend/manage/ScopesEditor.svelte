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

<div class="flex flex-col gap-2">
  <div class="flex flex-wrap gap-2">
    {#each known as scope (scope)}
      <button
        class="badge badge-lg gap-1"
        class:badge-primary={value.includes(scope)}
        class:badge-ghost={!value.includes(scope)}
        {disabled}
        onclick={() => toggle(scope)}
      >{scope}</button>
    {/each}
  </div>

  {#if !disabled}
    <div class="join">
      <input
        class="input input-sm input-bordered join-item font-mono"
        placeholder="add a scope"
        bind:value={adding}
        onkeydown={(e) => e.key === "Enter" && add()}
      />
      <button class="btn btn-sm join-item" onclick={add}>Add</button>
    </div>
  {/if}
</div>
