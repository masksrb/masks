<script>
import { preventDefault, stopPropagation } from "svelte/legacy";

import { XCircle } from "lucide-svelte";
import PromptHeader from "./PromptHeader.svelte";

let { prompt } = $props();
</script>

<PromptHeader heading="Login failed..." class="mb-3">
  {#snippet logo()}
    <div>
      <XCircle size="50" class="text-error" />
    </div>
  {/snippet}

  {#snippet subheading()}
    <p>Your login request is unsupported.</p>
  {/snippet}
</PromptHeader>

<button
  class="btn btn-lg"
  onclick={stopPropagation(preventDefault(() => window.history.back()))}
>
  go back
</button>
