<script>
  import Alert from "@/components/Alert.svelte";
  import PromptHeader from "../shared/PromptHeader.svelte";
  import { OctagonAlert, AlertTriangle } from "lucide-svelte";

  let { auth, settings } = $props();

  let denied = $derived(auth?.warnings?.includes("blocked-device"));
</script>

<PromptHeader
  heading={denied ? "Unable to continue..." : "Update your device..."}
  client={auth.client}
  redirectUri={auth.redirectUri}
  class="mb-6"
/>

{#if denied}
  <Alert type="error" icon={OctagonAlert}>
    Your device is blocked by <b>{auth?.settings?.name}</b>. You cannot
    continue.
  </Alert>
{:else}
  <Alert type="warn" icon={AlertTriangle}>
    Your device is not supported by <b>{auth?.settings?.name}</b>. You must use
    a different device to continue.
  </Alert>
{/if}

<div class="flex items-center gap-6 mt-6">
  {#if settings?.themeHomepage}
    <a href={settings?.themeHomepage} class="btn btn-lg btn-primary">
      Go home
    </a>
  {:else}
    <button onclick={() => history.back()} class="btn btn-error btn-lg text-lg">
      Go back
    </button>
  {/if}
</div>
