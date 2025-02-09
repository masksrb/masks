<script>
  import { preventDefault, stopPropagation } from "svelte/legacy";

  import { XCircle } from "lucide-svelte";
  import PromptHeader from "./PromptHeader.svelte";

  let { loadingError } = $props();
</script>

<PromptHeader heading="An error occurred..." class="mb-6">
  {#snippet logo()}
    <div>
      <XCircle size="50" class="text-error" />
    </div>
  {/snippet}

  {#snippet subheading()}
    <p>Your issue has been reported. It may be fixed by refreshing the page.</p>
  {/snippet}
</PromptHeader>

<div class="font-bold uppercase mb-3 text-xs">error message</div>
<code class="block w-full bg-black p-3 rounded-lg mb-6 text-green-300">
  {loadingError}
</code>

<button
  class="btn btn-lg"
  onclick={stopPropagation(preventDefault(() => window.location.reload()))}
>
  refresh the page
</button>
