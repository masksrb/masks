<script>
  let { children } = $props();
</script>

<div class="sheet px-6 py-14 text-center">
  <p class="mx-auto max-w-sm text-sm opacity-85">{@render children()}</p>
</div>
