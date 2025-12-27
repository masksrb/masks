<script>
import ProviderResult from "../ProviderResult.svelte";
import ClientSettings from "../ClientSettings.svelte";
import ScopesEditor from "../ScopesEditor.svelte";
import PasswordInput from "@/components/PasswordInput.svelte";

let { client, change, settings, ...props } = $props();
</script>

<div class="flex flex-col gap-3 pb-1.5">
  <ClientSettings {settings} {change} {client} />

  {#if client.providers?.length && client.allowSso}
    <div class="divider my-0 label-xs">SSO providers</div>

    <div class="rows-1.5">
      {#each client.providers || [] as provider}
        <ProviderResult {provider} {settings} link {...props} />
      {/each}
    </div>
  {/if}
</div>
