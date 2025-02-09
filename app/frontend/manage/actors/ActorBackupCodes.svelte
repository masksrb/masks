<script>
  import _ from "lodash-es";
  import { Trash2 as Trash } from "lucide-svelte";
  import Time from "@/components/Time.svelte";
  import { mutationStore, gql, getContextClient } from "@urql/svelte";

  let props = $props();
  let graphql = getContextClient();
  let actor = $state(props.actor);
  let saving = $state(false);
  let errors = $state();

  let save = (updates) => {
    saving = true;

    let update = mutationStore({
      client: graphql,
      query: gql`
        mutation ($input: ActorInput!) {
          actor(input: $input) {
            actor {
              id
              remainingBackupCodes
              savedBackupCodesAt
            }

            errors
          }
        }
      `,
      variables: { input: { ...updates, id: actor.id } },
    });

    update.subscribe((r) => {
      errors = r?.data?.actor?.errors;
      errors = errors?.length ? errors : null;
      saving = r?.fetching;

      if (!saving && !errors) {
        loading = false;
      }
    });
  };

  let deleteBackupCodes = () => {
    if (confirm("Remove all backup codes?")) {
      save({ resetBackupCodes: true });
    }
  };
</script>

{#if actor.savedBackupCodesAt}
  <div
    class="flex items-center gap-3 text-sm pr-1.5 bg-base-100 rounded-lg p-1.5 pl-3"
  >
    <span class="grow opacity-75"
      >{actor.remainingBackupCodes} remaining backup codes</span
    >

    <span class="label-xs">
      saved
      <Time timestamp={actor.savedBackupCodesAt} />
    </span>

    <button class="btn btn-xs" onclick={deleteBackupCodes}>
      <Trash size="14" />
    </button>
  </div>
{/if}
