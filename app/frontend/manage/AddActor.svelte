<script>
  import { run, preventDefault } from "svelte/legacy";
  import { goto } from "@mateothegreat/svelte5-router";

  import {
    PlusSquare as Plus,
    AlertTriangle,
    X,
    UserPlus,
    Save,
  } from "lucide-svelte";
  import { mutationStore, gql, getContextClient } from "@urql/svelte";
  import Mutation from "@/components/Mutation.svelte";
  import Alert from "@/components/Alert.svelte";

  let result = $state();
  let input = $state({ signup: true });
  let errors = $state();
  let saved = $state();

  let query = gql`
    mutation ($input: ActorInput!) {
      actor(input: $input) {
        actor {
          id
        }

        errors
      }
    }
  `;

  let gotoActor = (data) => {
    errors = data.errors;

    if (!data.errors.length) {
      saved = true;

      setTimeout(() => {
        goto(`/manage/actor/${data.actor.id}`);
      }, 1000);
    }
  };
</script>

<Mutation {query} {input} key="actor" onmutate={gotoActor}>
  {#snippet children({ mutate, mutating })}
    <form action="#" onsubmit={preventDefault(mutate)} class="w-full">
      <div class="flex items-center gap-3 w-full grow">
        <label class="input input-lg flex items-center gap-3 flex-grow">
          <input
            type="text"
            class="grow w-full"
            placeholder="enter a nickname or email for the actor..."
            bind:value={input.identifier}
          />
        </label>

        <button
          type="submit"
          class="btn btn-lg btn-success min-w-[90px]"
          disabled={saved || !input.identifier}
        >
          {#if !mutating && !saved}
            save
          {:else}
            <div class="loading loading-spinner"></div>
          {/if}
        </button>
      </div>

      {#if errors?.length}
        <Alert
          class="my-3"
          icon={AlertTriangle}
          type="error"
          errors={["Invalid identifier. Try another..."]}
        />
      {/if}
    </form>
  {/snippet}
</Mutation>
