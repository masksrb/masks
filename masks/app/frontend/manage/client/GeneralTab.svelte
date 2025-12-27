<script>
import ProviderResult from "../ProviderResult.svelte";
import ClientSettings from "../ClientSettings.svelte";
import ScopesEditor from "../ScopesEditor.svelte";
import PasswordInput from "@/components/PasswordInput.svelte";
import { Pencil } from "lucide-svelte";

let { client, change, settings, ...props } = $props();

let editingRedirects = $state();
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
    class="input-neutral"
    value={client.secret}
    onChange={(e) => change({ secret: e.target.value })}
  >
    {#snippet before()}
      <span class="label-xs opacity-75 w-[60px]">secret</span>
    {/snippet}
  </PasswordInput>

  <div class="h-auto box-snug bg-base-100">
    <div class={`cols-3 w-full ${editingRedirects ? "items-start" : ""}`}>
      <span
        class={`label-xs opacity-70 whitespace-nowrap ${editingRedirects ? "py-2" : ""}`}
        >redirect uris</span
      >

      {#if editingRedirects}
        <div class="rows items-start w-full">
          <div class="w-full grow">
            <textarea
              class="w-full bg-transparent text-sm focus:outline-none leading-snug textarea textarea-ghost"
              value={client.redirectUris.join("\n")}
              oninput={(e) => change({ redirectUris: e.target.value })}
              placeholder="..."
            ></textarea>
          </div>

          {#if !client.redirectUris}
            <label class="flex items-center gap-3">
              <input
                type="checkbox"
                class="toggle toggle-xs !toggle-warning !bg-neutral"
                checked={client.autofillRedirectUri}
                onclick={(e) =>
                  change({ autofillRedirectUri: e.target.checked })}
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
      {:else}
        <div class="w-full truncate text-sm font-mono cols-3 grow">
          {#each client.redirectUris as uri}
            <span class="text-base-content">{uri}</span>
          {/each}
        </div>

        <button
          class="btn btn-ghost btn-sm"
          onclick={() => (editingRedirects = !editingRedirects)}
          ><Pencil size="14" /></button
        >
      {/if}
    </div>
  </div>

  <ScopesEditor
    {settings}
    {client}
    scopes={{ required: client.requiredScopes, allowed: client.allowedScopes }}
    change={(r) => {
      change({
        allowedScopes: r.scopes.allowed,
        requiredScopes: r.scopes.required,
      });
    }}
  />
</div>

<div class="rows-3 my-1.5">
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
