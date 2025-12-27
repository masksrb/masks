<script>
import { AlertTriangle } from "lucide-svelte";
import Alert from "@/components/Alert.svelte";
import SSOHeader from "../shared/SSOHeader.svelte";
import PromptFocused from "../shared/PromptFocused.svelte";

let { settings, auth } = $props();
</script>

<PromptFocused>
  <div class="animate-fade-in-1s">
    <SSOHeader provider={auth?.provider}>
      {#snippet heading()}
        <div class="flex items-center gap-3">
          {#if auth.provider}
            <p>Log in with <b>{auth.provider.name}</b> failed...</p>
          {/if}
        </div>
      {/snippet}

      {#snippet alert()}
        <Alert
          type="error"
          icon={AlertTriangle}
          class="mt-6"
          errors={["Your single sign-on request is expired or invalid."]}
        />
      {/snippet}
    </SSOHeader>

    {#if settings?.themeHomepage}
      <div class="rows-3 justify-center mt-6">
        <a href={settings?.themeHomepage} class="btn btn-lg"> Go home </a>
      </div>
    {/if}
  </div></PromptFocused
>
