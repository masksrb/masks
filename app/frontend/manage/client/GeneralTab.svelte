<script>
  import ProviderResult from "../ProviderResult.svelte";
  import ClientSettings from "../ClientSettings.svelte";
  import ScopesEditor from "../ScopesEditor.svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";

  let { client, change, settings, ...props } = $props();
</script>

<div
  class="flex items-center pl-4 bg-base-200 mb-3 rounded-lg border border-neutral"
>
  <label class="flex items-center gap-3 py-1.5">
    <input
      type="checkbox"
      class="toggle !toggle-success !bg-neutral"
      checked={!client.internal}
      onclick={(e) => change({ internal: !e.target.checked })}
    />

    <div>
      <p class="font-bold text-sm">{client.internal ? "Internal" : "Public"}</p>

      <p class="label-xs">
        {#if client.internal}
          For internal use only...
        {:else}
          Supports OAuth/OpenID connect
        {/if}
      </p>
    </div>
  </label>
</div>

<div class="flex flex-col gap-3 pb-1.5">
  <PasswordInput
    value={client.secret}
    onChange={(e) => change({ secret: e.target.value })}
  >
    {#snippet before()}
      <span class="label-xs opacity-75 w-[60px]">secret</span>
    {/snippet}
  </PasswordInput>

  <div class="input input-bordered rounded-md h-auto pl-4 pr-1.5 py-3">
    <div class="flex items-start mb-3 gap-1.5">
      <span class="label-xs opacity-70 min-w-[60px]">redirect uris</span>

      <div class="w-full">
        <textarea
          class="w-full bg-transparent text-sm focus:outline-none leading-snug"
          value={client.redirectUris.join("\n")}
          oninput={(e) => change({ redirectUris: e.target.value })}
          placeholder="..."
        ></textarea>
      </div>
    </div>

    {#if !client.redirectUris}
      <label class="flex items-center gap-3">
        <input
          type="checkbox"
          class="toggle toggle-xs !toggle-warning !bg-neutral"
          checked={client.autofillRedirectUri}
          onclick={(e) => change({ autofillRedirectUri: e.target.checked })}
        />

        <span class="label-xs"
          >auto-populate with the first successful redirect uri</span
        >
      </label>
    {:else}
      <label class="flex items-center gap-3">
        <input
          type="checkbox"
          class="toggle toggle-xs !toggle-warning !bg-neutral"
          checked={client.fuzzyRedirectUri}
          onclick={(e) => change({ fuzzyRedirectUri: e.target.checked })}
        />

        <span class="label-xs">allow wildcards</span>
      </label>
    {/if}
  </div>

  <ScopesEditor {client} {change} {settings} />

  <div class="flex flex-col gap-3 pb-1.5">
    <ClientSettings {client} {change} {settings} />

    {#if client.providers?.length && client.allowSso}
      <div class="divider my-0 label-xs">SSO providers</div>

      <div class="rows-1.5">
        {#each client.providers || [] as provider}
          <ProviderResult {provider} {settings} link {...props} />
        {/each}
      </div>
    {/if}
  </div>
</div>
