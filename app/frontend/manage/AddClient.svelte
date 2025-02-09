<script>
  import { goto } from "@mateothegreat/svelte5-router";
  import { preventDefault } from "svelte/legacy";
  import { mutationStore, gql, getContextClient } from "@urql/svelte";
  import Mutation from "@/components/Mutation.svelte";
  import Alert from "@/components/Alert.svelte";

  let result = $state();
  let input = $state({});
  let errors = $state();
  let saved = $state();

  let query = gql`
    mutation ($input: ClientInput!) {
      client(input: $input) {
        client {
          id
        }

        errors
      }
    }
  `;

  let gotoClient = (data) => {
    errors = data.errors;

    if (!data.errors.length) {
      saved = true;

      setTimeout(() => {
        goto(`/manage/client/${data.client.id}`);
      }, 1000);
    }
  };
</script>

<Mutation {query} {input} key="client" onmutate={gotoClient}>
  {#snippet children({ mutate, mutating })}
    <form action="#" onsubmit={preventDefault(mutate)} class="w-full">
      <div class="flex items-center w-full grow gap-3">
        <label class="input input-lg flex items-center gap-3 flex-grow">
          <input
            type="text"
            class="grow w-full"
            placeholder="enter a name for the client..."
            bind:value={input.name}
          />
        </label>

        <button
          type="submit"
          class="btn btn-lg btn-success min-w-[90px]"
          disabled={saved || !input.name}
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
