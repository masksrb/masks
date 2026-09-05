<script>
  let { label = "Loading" } = $props();
</script>

<div class="grid place-items-center py-16" role="status">
  <span class="loading loading-spinner"></span>
  <span class="sr-only">{label}</span>
</div>
