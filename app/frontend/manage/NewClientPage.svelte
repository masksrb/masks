<script>
  import Page from "./Page.svelte";
  import { run, preventDefault } from "svelte/legacy";
  import { goto } from "@mateothegreat/svelte5-router";

  import { AlertTriangle, X, Handshake, Save } from "lucide-svelte";
  import { mutationStore, gql, getContextClient } from "@urql/svelte";

  let props = $props();
  let { search = () => {} } = props;

  let result = $state();
  let input = $state({});
  let client = getContextClient();
  let errors = $state();
  let loading;

  const addClient = (input) => {
    result = mutationStore({
      client,
      query: gql`
        mutation ($input: ClientInput!) {
          client(input: $input) {
            client {
              id
            }

            errors
          }
        }
      `,
      variables: { input },
    });
  };

  const handleResult = (result) => {
    if (!result) {
      return;
    }

    loading = true;
    errors = null;

    let data = result?.data?.client;

    if (!data) {
      return;
    }

    errors = data.errors;

    if (!errors?.length) {
      return goto(`/manage/client/${data.client.id}`);
    }

    loading = false;
  };

  run(() => {
    handleResult($result);
  });
</script>

<Page {...props}>
  <form
    action="#"
    onsubmit={preventDefault(() => addClient(input))}
    class="w-full"
  >
    <div class="flex items-center join w-full grow">
      <label
        class="input input-bordered flex items-center gap-3 flex-grow !outline-none
        join-item"
      >
        <Handshake />

        <input
          type="text"
          class="grow"
          placeholder="enter a name for the client..."
          bind:value={input.name}
        />
      </label>

      <div class="join">
        <button
          type="submit"
          class="join-item btn btn-info"
          disabled={!input.name}>save</button
        >
      </div>
    </div>

    {#if errors}
      <div
        class="alert border-2 text-error border-error rounded-lg mt-3 flex
      items-center gap-3"
      >
        <AlertTriangle />
        <ul>
          {#each errors as error}
            <li class="text-sm">{error}</li>
          {/each}
        </ul>
      </div>
    {/if}
  </form>
</Page>
