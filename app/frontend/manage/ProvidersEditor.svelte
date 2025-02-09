<script>
  import _ from "lodash-es";
  import Time from "@/components/Time.svelte";
  import Alert from "@/components/Alert.svelte";
  import CopyText from "@/components/CopyText.svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import Query from "@/components/Query.svelte";
  import Mutation from "@/components/Mutation.svelte";
  import { Github } from "lucide-svelte";
  import { gql } from "@urql/svelte";
  import ProviderResult from "./ProviderResult.svelte";
  import { ProviderFragment } from "@/util.js";

  let { settings, ...props } = $props();

  let query = gql`
    query {
      install {
        providerTypes {
          name
          type
        }
      }

      providers {
        nodes {
          ...ProviderFragment
        }
      }
    }

    ${ProviderFragment}
  `;

  let input = $state({});
  let isValid = () => {
    return (
      input.type && input.settings?.clientId && input.settings?.clientSecret
    );
  };

  let change = (vars) => {
    input = _.merge({}, input, vars);
  };

  let adding = $state();

  let added = (refresh) => {
    adding = false;
    refresh({});
  };

  let deleted = (refresh) => {
    refresh({});
  };
</script>

<Query {query} autoquery>
  {#snippet children({ result, refresh, loading })}
    <div class="flex items-center gap-3 mb-0.5">
      <span class="text-xs opacity-75 grow pl-1.5">Single sign-on</span>

      {#if !loading && result.providers?.nodes?.length}
        <button
          class="btn btn-xs btn-ghost"
          onclick={() => (adding = !adding)}
          disabled={loading}
        >
          {#if adding}
            cancel
          {:else}
            add a provider...
          {/if}
        </button>
      {/if}
    </div>

    {#if loading}
      <div
        class="flex flex-col gap-1.5 p-3 rounded-lg border-2 border-dashed border-base-100 text-center text-xs mt-1"
      >
        <div
          class="loading loading-spinner loading-sm opacity-50 mx-auto"
        ></div>
      </div>
    {:else if !adding && !result.providers?.nodes?.length}
      <div
        class="flex flex-col gap-1.5 p-3 rounded-lg border-2 border-dashed border-base-100 text-center text-xs mt-1"
      >
        <p class="opacity-75 whitespace-nowrap">
          <button class="underline font-bold" onclick={() => (adding = true)}>
            Add a provider
          </button> to enable single-sign on...
        </p>
      </div>
    {:else if adding}
      <div class="mt-1.5">
        <ProviderResult
          settings={result?.install}
          onadd={() => added(refresh)}
        />
      </div>
    {/if}

    {#if result?.providers?.nodes?.length}
      <div class="flex flex-col gap-1.5 pt-1.5">
        {#each result.providers.nodes as provider}
          {#key provider.id}
            <ProviderResult
              settings={result?.install}
              {provider}
              ondelete={() => deleted(refresh)}
            />
          {/key}
        {/each}
      </div>
    {/if}
  {/snippet}
</Query>
