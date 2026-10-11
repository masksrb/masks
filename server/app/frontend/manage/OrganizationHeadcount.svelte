<script>
  import { t } from "./lib/copy.js";

  let { organization, class: klass = "flex flex-col" } = $props();
</script>

<span class={klass}>
  <span>{t("organization_headcount.members", { count: organization.memberCount })}</span>
  {#if organization.pendingCount}
    <span class="text-xs opacity-75">{t("organization_headcount.invited", { count: organization.pendingCount })}</span>
  {/if}
</span>
