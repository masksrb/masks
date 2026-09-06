<script>
  let { checked = $bindable(false), label, onchange = null } = $props();
</script>

<label class="flex cursor-pointer items-center gap-2 text-sm">
  <input
    type="checkbox"
    class="toggle toggle-sm"
    bind:checked
    onchange={onchange ? (event) => onchange(event.currentTarget.checked) : undefined}
  />
  {label}
</label>
