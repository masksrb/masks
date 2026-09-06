<script>
import PromptHeader from "../shared/PromptHeader.svelte";

let { login } = $props();
</script>

<PromptHeader {login} />

<p class="waiting">
  <span class="spinner"></span>
  {login.t("waiting")}
</p>

