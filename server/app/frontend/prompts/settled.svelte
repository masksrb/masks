<script>
import PromptHeader from "../shared/PromptHeader.svelte";

let { login } = $props();
</script>

<PromptHeader heading="Signed in" {login} />

<p class="flex items-center gap-2 text-sm opacity-75">
  <span class="loading loading-spinner loading-sm"></span>
  Taking you back...
</p>
