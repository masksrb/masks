<script>
  import _ from "lodash-es";
  import Icon from "@iconify/svelte";
  import Time from "@/components/Time.svelte";
  import Alert from "@/components/Alert.svelte";
  import CopyText from "@/components/CopyText.svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import { Ban, Trash2, Settings2, X, Github } from "lucide-svelte";
  import { gql } from "@urql/svelte";
  import Mutation from "@/components/Mutation.svelte";
  import Deletion from "./Deletion.svelte";
  import { iconifyProvider, ProviderFragment } from "@/util.js";

  let { provider, settings, ...props } = $props();

  let providerTypes = $derived(
    Object.fromEntries(settings?.providerTypes?.map((t) => [t.type, t]))
  );
  let editing = $state();
  let input = $state(
    provider
      ? _.pick(provider, ["id", "type", "name", "common", "settings"])
      : {}
  );
  let mutate = gql`
    mutation ($input: ProviderInput!) {
      provider(input: $input) {
        provider {
          ...ProviderFragment
        }

        errors
      }
    }

    ${ProviderFragment}
  `;

  let isValid = () => {
    return input.type;
  };

  let change = (vars) => {
    input = _.merge({}, input, vars);
  };

  let onmutate = (result) => {
    if (!result.error && !provider) {
      props.onadd?.(result.provider);
    }
  };
</script>

<Mutation key="provider" query={mutate} {onmutate} {input}>
  {#snippet children({ mutate })}
    {#if provider}
      <div class="bg-base-300 px-3 pt-1 pb-1 rounded-lg">
        <div class="flex items-center gap-3">
          <div
            class="bg-base-100 rounded-lg p-[4px] w-[30px] h-[30px] fill-white shadow-inner"
          >
            <Icon icon={iconifyProvider(provider)} width="100%" height="100%" />
          </div>
          <div class="grow">
            <b class="text-xs truncate">{provider.name}</b>
            <CopyText text={provider.callbackUri} />
          </div>

          <div class="flex flex-col items-end">
            <span class="text-xs opacity-75 truncate"
              ><Time timestamp={provider.createdAt} ago="old" /></span
            >
            {#if provider.disabled}
              <b class="text-xs truncate text-warning">disabled</b>
            {:else if !provider.setup}
              <b class="text-xs truncate text-info">setup required</b>
            {:else}
              <b class="text-xs truncate text-success">active</b>
            {/if}
          </div>
          <button
            class="btn btn-sm btn-icon"
            onclick={() => (editing = !editing)}
          >
            {#if editing}
              <X size="18" />
            {:else}
              <Settings2 size="18" />
            {/if}
          </button>
        </div>

        {#if editing}
          {@const type = providerTypes[input.type]}
          <div class="flex flex-col gap-1.5">
            <Deletion
              type={"Provider"}
              id={provider?.id}
              ondelete={props.ondelete}
              confirm="Are you sure you want to delete this provider?"
            >
              {#snippet children({ deletion, deleting })}
                <div class="mb-0.5 mt-1.5 rounded-full p-1.5 px-3 bg-black">
                  <div class="flex items-center gap-3 text-sm">
                    <label
                      class="label cursor-pointer flex items-center gap-3 grow"
                    >
                      <input
                        type="checkbox"
                        class="toggle toggle-xs"
                        disabled={provider.disabledAt}
                        checked={provider.common}
                        onclick={(e) => change({ common: !provider.common })}
                      />
                      <span class="opacity-75 label-text-alt grow truncate">
                        {#if provider.disabled}
                          <b class="text-warning">Disabled</b>
                          <Time timestamp={provider.disabledAt} />
                        {:else}
                          {provider.common ? "Enabled" : "Enable"} for all clients
                        {/if}
                      </span>
                    </label>

                    {#if provider.disabled}
                      <button
                        class="btn btn-error btn-xs btn-outline"
                        disabled={!provider.disabled}
                        onclick={deletion}
                      >
                        Delete
                      </button>
                    {/if}

                    <button
                      class={`btn btn-xs ${provider.disabled ? "btn-outline" : "btn-ghost"}`}
                      onclick={() =>
                        mutate(
                          provider.disabled
                            ? { enabled: true }
                            : { disabled: true }
                        )}
                    >
                      {#if provider.disabled}
                        Enable
                      {:else}
                        Disable
                      {/if}
                    </button>

                    <button
                      class={`btn btn-xs btn-success ${provider.disabled ? "btn-outline" : ""}`}
                      onclick={() => mutate(input)}
                    >
                      Save
                    </button>
                  </div>
                </div>
              {/snippet}
            </Deletion>
            <label
              class="input input-sm input-bordered flex items-center gap-3"
            >
              <div class="text-xs opacity-75">Name</div>

              <input
                class="placeholder:opacity-75"
                placeholder={type.name}
                bind:value={input.name}
              />
            </label>

            <PasswordInput
              class="input-sm"
              value={provider.settings?.clientId}
              onChange={(e) =>
                change({ settings: { clientId: e.target.value } })}
            >
              {#snippet before()}
                <span class="label-text-alt opacity-70 whitespace-nowrap"
                  >App ID</span
                >
              {/snippet}
            </PasswordInput>

            <PasswordInput
              class="input-sm mb-2"
              value={provider.settings?.clientSecret}
              onChange={(e) =>
                change({ settings: { clientSecret: e.target.value } })}
            >
              {#snippet before()}
                <span class="label-text-alt opacity-70 whitespace-nowrap"
                  >App secret</span
                >
              {/snippet}
            </PasswordInput>
          </div>
        {/if}
      </div>
    {:else}
      <div
        class="flex flex-col gap-1.5 p-1.5 rounded-lg border-2 border-dashed border-base-100 mt-0.5 bg-base-100 bg-opacity-50"
      >
        <div class="flex items-center gap-1.5">
          <div
            class={`w-10 h-10 p-2 bg-base-300 fill-white rounded-lg ${input?.type ? "" : "opacity-50"}`}
          >
            <Icon
              icon={input?.type
                ? iconifyProvider(input)
                : "solar:list-line-duotone"}
              width="100%"
              height="100%"
            />
          </div>

          <select
            class="select select-sm select-ghost !outline-none grow font-bold"
            onchange={(e) => (input = { ...input, type: e.target.value })}
          >
            <option selected={!input.type} disabled>Select a type...</option>
            {#each Object.values(providerTypes) as type}
              <option value={type.type} selected={type.type == input.type}
                >{type.name}</option
              >
            {/each}
          </select>

          <button
            class="btn btn-sm btn-success"
            disabled={!isValid()}
            onclick={() => mutate(input)}
          >
            add
          </button>
        </div>

        {#if input.type}
          <label class="input input-sm flex items-center gap-3">
            <div class="text-xs opacity-75">Name</div>

            <input
              class="placeholder:opacity-75"
              placeholder="optional"
              bind:value={input.name}
            />
          </label>
        {/if}
      </div>
    {/if}
  {/snippet}
</Mutation>
