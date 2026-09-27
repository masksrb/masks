<script>
  let { label = null, value, options, onchange, disabled = false, name = null } = $props();
</script>

<label class="flex min-w-0 flex-col gap-1.5">
  {#if label}<span class="field-label">{label}</span>{/if}

  <select
    class="select select-sm w-full"
    {value}
    {disabled}
    aria-label={label ? null : name}
    onchange={(event) => onchange(event.currentTarget.value)}
  >
    {#each options as [key, text, off = false] (key)}
      <option value={key} disabled={off}>{text}</option>
    {/each}
  </select>
</label>
