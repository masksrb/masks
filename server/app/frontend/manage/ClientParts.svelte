<script>
  import { t } from "./lib/copy.js";
  import Link from "./ui/Link.svelte";

  let { clientId, part = null } = $props();

  const PARTS = [
    [null, "", "general"],
    ["access", "/access", "access"],
    ["endpoints", "/endpoints", "endpoints"],
    ["usage", "/usage", "usage"],
  ];
</script>

<nav class="settings-tabs" aria-label={t("client.parts.label")}>
  {#each PARTS as [key, path, label] (label)}
    <Link to={`/clients/${clientId}${path}`} class="settings-tab {(part ?? null) === key ? 'settings-tab-on' : ''}">
      {t(`client.parts.${label}`)}
    </Link>
  {/each}
</nav>
