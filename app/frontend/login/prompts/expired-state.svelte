<script>
  import { preventDefault, stopPropagation } from "svelte/legacy";

  import { OctagonAlert as Icon } from "lucide-svelte";
  import Alert from "@/components/Alert.svelte";
  import PromptLoading from "../shared/PromptLoading.svelte";
  import PromptHeader from "../shared/PromptHeader.svelte";
  import { onMount } from "svelte";
  import { redirectTimeout } from "@/lib";

  let { auth } = $props();

  let loading = $state(true);

  onMount(() => {
    redirectTimeout(() => {
      window.location.reload();
    }, 150);

    setTimeout(() => {
      loading = false;
    }, 1000);
  });
</script>

{#if loading}
  <PromptLoading />
{:else}
  <PromptHeader
    heading="Session expired..."
    prefix="during access to "
    client={auth.client}
    class="mb-3"
  />

  <Alert type="error" icon={Icon} class="mb-3">
    Your session has expired. Refresh the page and try again to continue...
  </Alert>

  <button
    class="btn btn-lg"
    onclick={stopPropagation(preventDefault(() => window.location.reload()))}
  >
    refresh the page
  </button>
{/if}
