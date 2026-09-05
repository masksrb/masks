<script>
  let {
    label,
    value = $bindable(""),
    type = "text",
    onsave = null,
    save = "Save",
    ...rest
  } = $props();
</script>

<label class="flex flex-col gap-1.5">
  <span class="text-xs font-medium opacity-70">{label}</span>

  {#if onsave}
    <div class="join">
      <input class="input input-sm join-item w-full" {type} bind:value {...rest} />
      <button type="button" class="btn btn-sm join-item" onclick={onsave}>{save}</button>
    </div>
  {:else}
    <input class="input input-sm w-full" {type} bind:value {...rest} />
  {/if}
</label>
