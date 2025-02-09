<script>
  import Page from "./Page.svelte";
  import { run, preventDefault } from "svelte/legacy";
  import { goto } from "@mateothegreat/svelte5-router";

  import { AlertTriangle, X, UserPlus, Save } from "lucide-svelte";
  import { mutationStore, gql, getContextClient } from "@urql/svelte";

  let props = $props();
  let { search = () => {} } = props;

  let result = $state();
  let input = $state({ signup: true });
  let client = getContextClient();
  let errors = $state();
  let loading;

  const addActor = (input) => {
    result = mutationStore({
      client,
      query: gql`
        mutation ($input: ActorInput!) {
          actor(input: $input) {
            actor {
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

    let data = result?.data?.actor;

    if (!data) {
      return;
    }

    errors = data.errors;

    if (!errors?.length) {
      return goto(`/manage/actor/${data.actor.id}`);
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
    onsubmit={preventDefault(() => addActor(input))}
    class="w-full"
  >
    <div class="flex items-center join w-full grow">
      <label
        class="input input-bordered flex items-center gap-3 flex-grow
        join-item"
      >
        <UserPlus />

        <input
          type="text"
          class="grow"
          placeholder="enter a nickname or email for the actor..."
          bind:value={input.identifier}
        />
      </label>

      <div class="join">
        <button
          type="submit"
          class="join-item btn btn-secondary"
          disabled={!input.identifier}><Save size="15" /> save</button
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
