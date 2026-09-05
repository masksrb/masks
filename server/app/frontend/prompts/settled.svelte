<script>
import PromptHeader from "../shared/PromptHeader.svelte";

let { login } = $props();
</script>

<PromptHeader heading="Signed in" {login} />

<p class="waiting">
  <span class="spinner"></span>
  Taking you back
</p>
