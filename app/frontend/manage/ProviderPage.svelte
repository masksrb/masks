<script>
  import { copy } from "svelte-copy";
  import _ from "lodash-es";
  import {
    Ban,
    Check,
    CircleSlash,
    CirclePause,
    CirclePlay,
    ClipboardX,
    ClipboardCheck,
    ClipboardCopy,
    LogOut,
    RotateCcw,
    MailPlus,
    Trash2 as Trash,
    User,
    Handshake,
    SquarePlus,
    Trash2,
  } from "lucide-svelte";
  import Page from "./Page.svelte";
  import CopyButton from "@/components/CopyButton.svelte";
  import CopyText from "@/components/CopyText.svelte";
  import Alert from "@/components/Alert.svelte";
  import Time from "@/components/Time.svelte";
  import Identicon from "@/components/Identicon.svelte";
  import ProviderIcon from "@/components/ProviderIcon.svelte";
  import Query from "@/components/Query.svelte";
  import Mutation from "@/components/Mutation.svelte";
  import Deletion from "./Deletion.svelte";
  import { ProviderFragment } from "@/lib";
  import { queryStore, gql, getContextClient } from "@urql/svelte";
  import ProviderResult from "./ProviderResult.svelte";
  import { getContext } from "svelte";

  let { params, ...props } = $props();

  let query = gql`
    query ($id: String!) {
      provider(id: $id) {
        ...ProviderFragment

        settings

        clients {
          nodes {
            id
            name
          }
        }
      }

      server {
        providerTypes {
          name
          type
        }
      }
    }

    ${ProviderFragment}
  `;

  let mutation = gql`
    mutation ($input: ProviderInput!) {
      provider(input: $input) {
        provider {
          ...ProviderFragment

          clients {
            nodes {
              id
              name
            }
          }
        }

        errors
      }
    }

    ${ProviderFragment}
  `;

  let modules = import.meta.glob("./providers/*.svelte");
  let Component = $state();
  let original = $state();
  let provider = $state();
  let settings = $state();
  let input = $state({});
  let assignClient = $state();

  let { root } = getContext("page");

  let path = $derived(`${root}/sso/${params[0]}`);

  let change = (vars) => {
    input = _.merge(input, vars);
    provider = _.merge(provider, input);
  };

  let load = async (result) => {
    provider = result.provider;
    original = _.cloneDeep(result.provider);
    settings = result.server;
    input = provider
      ? _.pick(provider, ["id", "type", "name", "common", "settings"])
      : {};

    Component = (await modules[`./providers/${provider.type}.svelte`]?.())
      ?.default;
  };

  let onmutate = (result) => {};
</script>

<Query {query} variables={{ id: params[0] }} onload={load}>
  {#snippet children({ result, loading })}
    <Page {...props} {loading} notFound={!provider && !loading}>
      {#if provider}
        <Mutation key="provider" query={mutation} {onmutate} {input}>
          {#snippet children({ mutate })}
            <ProviderResult {...props} {settings} {provider} {change} editing />

            <div class="grow box-snug bg-base-100 mt-0.5">
              <div class="pl-1.5">
                <CopyText label="Callback URI" text={provider.callbackUri} />
              </div>
            </div>

            <div class="flex flex-col gap-1.5">
              <Deletion
                type={"Provider"}
                id={provider?.id}
                confirm="Are you sure you want to delete this provider?"
                after={`${root}/sso`}
              >
                {#snippet children({ deletion, deleting })}
                  <div class="mb-0.5 mt-1.5 rounded-lg p-1.5 px-3 bg-black">
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
                        <span class="opacity-75 label-xs grow truncate">
                          {#if provider.disabled}
                            <b class="text-warning">Disabled</b>
                            <Time timestamp={provider.disabledAt} />
                          {:else}
                            {provider.common
                              ? "Enabled for all clients"
                              : "Enabled for some clients"}
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
                              ? { id: provider.id, enabled: true }
                              : { id: provider.id, enabled: false },
                            { merge: false }
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
                        disabled={_.isEqual(original, provider)}
                      >
                        Save
                      </button>
                    </div>

                    {#if !provider.common && !provider.disabled}
                      <div class="divider my-0"></div>

                      <label
                        class="input input-bordered input-sm flex items-center gap-3"
                      >
                        <p class="whitespace-nowrap label-sm">Enable for</p>

                        <input
                          bind:value={assignClient}
                          type="text"
                          class="grow w-full"
                          placeholder="Client ID..."
                        />

                        <button
                          type="button"
                          class="btn btn-xs -mr-1.5"
                          disabled={!assignClient}
                          onclick={() =>
                            mutate(
                              { id: provider.id, assignClient },
                              { merge: false }
                            )}
                        >
                          Enable
                        </button>
                      </label>

                      <div class="rows-1.5 mt-3 mb-1.5">
                        {#each provider.clients?.nodes || [] as client}
                          <div class="box-snug bg-base-300 cols-3">
                            <a
                              href={`${props.root}/client/${client.id}`}
                              class="text-xs font-bold hover:underline focus:underline"
                              >{client.name}</a
                            >
                            <p class="label-xs font-mono grow">{client.id}</p>

                            <button
                              onclick={() =>
                                mutate(
                                  { id: provider.id, removeClient: client.id },
                                  { merge: false }
                                )}
                              class="btn btn-square btn-neutral btn-xs text-error"
                            >
                              <Trash2 size="18" />
                            </button>
                          </div>
                        {/each}
                      </div>
                    {/if}
                  </div>
                {/snippet}
              </Deletion>

              {#if Component}
                <div class="box bg-neutral rows-1.5">
                  <Component
                    settings={result.server}
                    provider={result.provider}
                    {change}
                  />
                </div>
              {/if}
            </div>
          {/snippet}
        </Mutation>
      {/if}
    </Page>
  {/snippet}
</Query>
