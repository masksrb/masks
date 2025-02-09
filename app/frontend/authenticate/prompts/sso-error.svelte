<script>
  import { AlertTriangle } from "lucide-svelte";
  import Alert from "@/components/Alert.svelte";
  import SSOHeader from "../shared/SSOHeader.svelte";
  import PromptFocused from "../shared/PromptFocused.svelte";

  let { settings, backend } = $props();

  let errors = {
    "invalid-sso": "Your single sign-on request is expired or invalid.",
  };
</script>

<PromptFocused>
  <div class="animate-fade-in-1s">
    <SSOHeader provider={backend?.provider}>
      {#snippet heading()}
        <div class="flex items-center gap-3">
          {#if backend.provider}
            <p>Log in with <b>{backend.provider.name}</b> failed...</p>
          {/if}
        </div>
      {/snippet}

      {#snippet alert()}
        <Alert
          type="error"
          icon={AlertTriangle}
          class="mt-6"
          errors={[errors[backend.error] || backend.error]}
        />
      {/snippet}
    </SSOHeader>

    {#if backend.origin || settings?.theme?.url}
      <div class="rows-3 justify-center mt-6">
        {#if backend.origin}
          <a href={backend.origin} class="btn btn-lg"> Go back </a>
        {:else if settings?.theme?.url || true}
          <a href={settings?.theme?.url} class="btn btn-lg"> Go home </a>
        {/if}
      </div>
    {/if}
  </div></PromptFocused
>
