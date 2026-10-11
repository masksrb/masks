<script>
  import { t } from "../lib/copy.js";
  let { text, label = t("ui.more_about") } = $props();

  const id = $props.id();
</script>

<span class="tip">
  <button type="button" class="tip-mark" aria-label={label} aria-describedby={id}>?</button>
  <span class="tip-body" role="tooltip" {id}>{text}</span>
</span>
