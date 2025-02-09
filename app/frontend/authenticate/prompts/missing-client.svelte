<script>
  import PromptHeader from "../shared/PromptHeader.svelte";
</script>

<PromptHeader heading="Login failed" class="mb-3" />

<p class="text-xl mb-12">
  A <code>client</code> must be supplied in the request.
</p>

<div class="flex items-center gap-6">
  <button onclick={() => history.back()} class="btn btn-error btn-lg text-lg">
    Go back
  </button>
</div>
