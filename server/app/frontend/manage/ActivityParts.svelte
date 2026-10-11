<script>
  import { t } from "./lib/copy.js";
  import Link from "./ui/Link.svelte";

  let { part } = $props();
</script>

<nav class="settings-tabs" aria-label={t("activity.title")}>
  <Link to="/activity" class="settings-tab {part === 'log' ? 'settings-tab-on' : ''}">{t("activity.parts.log")}</Link>
  <Link to="/activity/streams" class="settings-tab {part === 'streams' ? 'settings-tab-on' : ''}">{t("activity.parts.streams")}</Link>
</nav>
