<script>
  import { goto } from "@mateothegreat/svelte5-router";
  import { preventDefault } from "svelte/legacy";
  import { gql } from "@urql/svelte";
  import Query from "@/components/Query.svelte";
  import Mutation from "@/components/Mutation.svelte";
  import Alert from "@/components/Alert.svelte";
  import { getContext } from "svelte";
  import { AlertTriangle } from "lucide-svelte";

  let input = $state({});
  let errors = $state();
  let saved = $state();
  let { root } = getContext("page");

  let settings = gql`
    query {
      server {
        providerTypes {
          name
          type
        }
      }
    }
  `;
  let query = gql`
    mutation ($input: ProviderInput!) {
      provider(input: $input) {
        provider {
          id
        }

        errors
      }
    }
  `;

  let gotoProvider = (data) => {
    if (!data.errors.length) {
      saved = true;

      setTimeout(() => {
        goto(`${root}/sso/${data.provider.id}`);
      }, 1000);
    } else {
      errors = data.errors;
    }
  };
</script>

<Query query={settings} key={"server"} autoquery>
  {#snippet children({ result })}
    <Mutation {query} {input} key="provider" onmutate={gotoProvider}>
      {#snippet children({ mutate, mutating })}
        <form action="#" onsubmit={preventDefault(mutate)} class="w-full">
          <div class="flex items-center gap-1.5 mb-1.5 -mt-1.5">
            <select
              class="select select-ghost select-sm !outline-none grow w-full"
              onchange={(e) => (input.type = e.target.value)}
            >
              <option disabled selected>Choose a type...</option>

              {#each result.providerTypes as type}
                <option value={type.type}>{type.name}</option>
              {/each}
            </select>
          </div>

          <div class="flex items-center w-full grow gap-3">
            <label class="input input-lg flex items-center gap-3 flex-grow">
              <input
                type="text"
                class="grow w-full"
                placeholder="enter a name for the provider..."
                bind:value={input.name}
              />
            </label>

            <button
              type="submit"
              class="btn btn-lg btn-success min-w-[90px]"
              disabled={saved || !input.name || !input.type}
            >
              {#if !mutating && !saved}
                save
              {:else}
                <div class="loading loading-spinner"></div>
              {/if}
            </button>
          </div>

          {#if errors}
            <Alert
              class="my-3"
              icon={AlertTriangle}
              type="error"
              errors={["Invalid name. Try another..."]}
            />
          {/if}
        </form>
      {/snippet}
    </Mutation>
  {/snippet}
</Query>
