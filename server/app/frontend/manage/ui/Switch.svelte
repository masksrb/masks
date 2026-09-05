<script>
  let { checked = $bindable(false), label } = $props();
</script>

<label class="flex cursor-pointer items-center gap-2 text-sm">
  <input type="checkbox" class="toggle toggle-sm" bind:checked />
  {label}
</label>
