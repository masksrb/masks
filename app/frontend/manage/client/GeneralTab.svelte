<script>
  import ScopesEditor from "../ScopesEditor.svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";

  let { client, change, settings, ...props } = $props();
</script>

<div
  class="flex items-center pl-4 bg-base-200 mb-3 rounded-lg border border-neutral"
>
  <span class="label-text-alt opacity-70 min-w-[60px]">type</span>

  <select
    class="select select-ghost rounded-l-none w-full grow"
    onchange={(e) => change({ type: e.target.value })}
  >
    {#each settings?.clients?.types as type}
      <option selected={type == client?.type}>{type}</option>
    {/each}
  </select>
</div>

<div class="flex flex-col gap-3">
  <PasswordInput
    value={client.secret}
    onChange={(e) => change({ secret: e.target.value })}
  >
    {#snippet before()}
      <span class="label-text-alt opacity-75 w-[60px]">secret</span>
    {/snippet}
  </PasswordInput>

  <div class="input input-bordered rounded-md h-auto pl-4 pr-1.5 py-3">
    <div class="flex items-start mb-3 gap-1.5">
      <span class="label-text-alt opacity-70 min-w-[60px]">redirect uris</span>

      <div class="w-full">
        <textarea
          class="w-full bg-transparent text-sm focus:outline-none leading-snug"
          value={client.redirectUris}
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

        <span class="text-xs opacity-75"
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

        <span class="text-xs opacity-75">allow wildcards</span>
      </label>
    {/if}
  </div>

  <ScopesEditor {client} {change} {settings} />
</div>
