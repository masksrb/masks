<script>
  import { Trash2 as Trash, Cog, X, Plus, Info } from "lucide-svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import Alert from "@/components/Alert.svelte";

  let { client, settings, change, ...props } = $props();
  let scopes = $derived(props.scopes || client?.scopes || {});
  let required = $derived(scopes.required || []);
  let allowed = $derived(scopes.allowed || []);
  let all = $derived(Array.from(new Set([...required, ...allowed])).sort());
  let value = $state("");
  let invalid = $derived(value && value.includes(" "));
  let valid = $derived(value && !invalid);
  let adding = $state();

  let removeScope = (scope) => {
    return (e) => {
      change({
        scopes: {
          required: required.filter((s) => s !== scope).filter(Boolean),
          allowed: allowed.filter((s) => s !== scope).filter(Boolean),
        },
      });
    };
  };

  let toggleScope = (scope) => {
    return (e) => {
      if (e.target.checked || props.required) {
        change({
          scopes: {
            required: Array.from(new Set([...required, scope])).filter(Boolean),
            allowed: allowed.filter((s) => s !== scope).filter(Boolean),
          },
        });
      } else {
        change({
          scopes: {
            required: required.filter((s) => s !== scope).filter(Boolean),
            allowed: Array.from(new Set([...allowed, scope])).filter(Boolean),
          },
        });
      }
    };
  };

  let addScope = () => {
    change({
      scopes: { required, allowed: Array.from(new Set([...allowed, value])) },
    });

    if (props.required) {
      toggleScope(value);
    }

    value = null;
  };

  let requiredScope = (scope) => {
    return scopes.required.includes(scope);
  };

  let subjectTypes = {
    "public-uuid": {
      name: "UUID",
      desc: "Actors are distinguished by a globally unique ID...",
    },
    "public-identifier": {
      name: "Identifier",
      desc: "Actor IDs will include their unique nickname or login email...",
    },
    "pairwise-uuid": {
      name: "Masked UUID",
    },
  };

  let advanced = $state();
</script>

<div class="bg-base-200 py-3 px-4 rounded-lg">
  <div class="flex items-center gap-3 mb-3">
    {#if all.length}
      <div class="text-xs opacity-75 grow">
        scopes {#if client}&amp; data{/if}
      </div>
    {/if}

    {#if client}
      <button
        class="btn btn-xs btn-neutral"
        type="button"
        onclick={() => (advanced = !advanced)}
        >{#if advanced}<X size="16" />{:else}<Cog
            size="16"
            class=""
          />{/if}</button
      >
    {/if}
  </div>

  {#if advanced && settings}
    <Alert type="neutral" class="mb-3 -mx-4 rounded-none">
      <div class="flex items-center gap-1.5 mb-1.5 -mt-1.5">
        <span class="opacity-75 text-sm grow"> ID format</span>

        <select
          class="select select-sm select-ghost !outline-none"
          onchange={(e) => change({ subjectType: e.target.value })}
        >
          {#each settings?.clients?.subjectTypes as type}
            <option value={type} selected={type == client.subjectType}
              >{subjectTypes[type].name}</option
            >
          {/each}
        </select>
      </div>

      {#if client.subjectType.startsWith("pairwise-")}
        <p class="label-text-alt opacity-75 text-xs mb-3">
          Identifiers will be generated using this algorithm: <span
            class="font-mono">SHA256(sector + uuid + salt)</span
          >
        </p>
      {:else}
        <p class="label-text-alt opacity-75">
          {subjectTypes[client.subjectType].desc}
        </p>
      {/if}

      {#if client.subjectType.startsWith("pairwise-")}
        <label
          class="input input-ghost input-bordered input-sm flex items-center gap-3 mb-3"
        >
          <p class="label-text-alt opacity-75">sector</p>
          <input
            type="text"
            value={client.sectorIdentifier}
            oninput={(e) => change({ sectorIdentifier: e.target.value })}
            class="w-full min-w-0 py-1.5 pb-2 !outline-none text-black dark:text-white"
          />
        </label>

        <PasswordInput
          value={client.pairwiseSalt}
          class="input-sm input-ghost mb-1.5"
          onChange={(e) => change({ pairwiseSalt: e.target.value })}
        >
          {#snippet before()}
            <p class="label-text-alt opacity-75">salt</p>
          {/snippet}
        </PasswordInput>
      {/if}
    </Alert>
  {/if}
  {#each all as scope}
    {#key scope}
      <div class="text-sm flex items-center gap-1.5 mb-1.5">
        <span
          class={`grow font-mono truncate ${requiredScope(scope) ? "font-bold" : ""}`}
        >
          {scope}
        </span>

        {#if !props.required}
          <div class="text-xs opacity-75 italic font-sans">
            {#if requiredScope(scope)}
              required
            {:else}
              require?
            {/if}
          </div>

          <input
            type="checkbox"
            class="toggle toggle-xs"
            checked={requiredScope(scope)}
            onchange={toggleScope(scope)}
          />
        {/if}

        <button onclick={removeScope(scope)} class="btn btn-xs text-error"
          ><Trash size="14" /></button
        >
      </div>
    {/key}
  {/each}

  {#if all.length}
    <div class="divider my-1.5"></div>
  {/if}

  <div class="flex items-center gap-3 mb-1.5">
    <input
      type="text"
      class="input input-sm w-full"
      placeholder="add a scope..."
      bind:value
    />

    <button
      type="button"
      class="btn btn-sm btn-primary"
      disabled={!valid}
      onclick={addScope}
    >
      {#if invalid}
        <X size="18" />
      {:else}
        add
      {/if}
    </button>
  </div>
</div>
