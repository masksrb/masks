<script>
  import { t } from "./lib/copy.js";
  import Link from "./ui/Link.svelte";

  let { organization, children } = $props();
</script>

<span class="flex flex-wrap items-center gap-2">
  <Link to={`/organizations/${organization.key}`} class="link link-hover font-medium">{organization.name}</Link>
  {#if organization.ownerCount === 0}
    <span class="badge badge-warning badge-xs">{t("organization_cell.no_owner")}</span>
  {/if}
</span>
<span class="font-mono text-xs opacity-75">{organization.key}</span>
{@render children?.()}
