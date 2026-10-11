<script>
  import Link from "./Link.svelte";

  let { base, part = null, parts, label } = $props();
</script>

<nav class="settings-tabs" aria-label={label}>
  {#each parts as [key, path, name] (path)}
    <Link
      to={`${base}${path}`}
      class="settings-tab {(part ?? null) === key ? 'settings-tab-on' : ''}"
      aria-current={(part ?? null) === key ? "page" : undefined}
    >
      {name}
    </Link>
  {/each}
</nav>
