<script>
  import { t } from "../lib/copy.js";
  let { label = t("ui.loading") } = $props();
</script>

<div class="grid place-items-center py-16" role="status">
  <span class="loading loading-spinner"></span>
  <span class="sr-only">{label}</span>
</div>
