<script>
  import _ from "lodash-es";
  import { Trash2 as Trash, Cog, X, Plus, Info } from "lucide-svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import Alert from "@/components/Alert.svelte";

  let { client, change, ...props } = $props();

  let scopes = $derived(props.scopes || client?.scopes || {});
  let required = $derived(_.castArray(scopes.required).filter(Boolean));
  let allowed = $derived(_.castArray(scopes.allowed).filter(Boolean));
  let all = $derived(Array.from(new Set([...required, ...allowed])).sort());
  let value = $state("");
  let invalid = $derived(value && value.includes(" "));
  let valid = $derived(value && !invalid);

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
</script>

<div class="bg-base-200 py-3 px-4 rounded-lg">
  {#if props.title}
    <div class="flex items-center gap-3 mb-3">
      <div class="label-xs grow">
        {props.title}
      </div>
    </div>
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
          <div class="label-xs italic font-sans">
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
      class="input input-neutral input-sm w-full"
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
