<script>
  import { plural } from "./lib/format.js";

  let { organization, class: klass = "flex flex-col" } = $props();
</script>

<span class={klass}>
  <span>{plural(organization.memberCount, "member")}</span>
  {#if organization.pendingCount}
    <span class="text-xs opacity-75">{organization.pendingCount} invited</span>
  {/if}
</span>
