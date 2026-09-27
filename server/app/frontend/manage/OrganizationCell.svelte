<script>
  import Link from "./ui/Link.svelte";

  let { organization, children } = $props();
</script>

<span class="flex flex-wrap items-center gap-2">
  <Link to={`/organizations/${organization.key}`} class="link link-hover font-medium">{organization.name}</Link>
  {#if organization.ownerCount === 0}
    <span class="badge badge-warning badge-xs">no owner</span>
  {/if}
</span>
<span class="font-mono text-xs opacity-75">{organization.key}</span>
{@render children?.()}
