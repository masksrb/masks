<script>
  import { copy } from "svelte-copy";
  import {
    ClipboardX,
    ClipboardCheck,
    ClipboardCopy,
    LogOut,
    RotateCcw,
    MailPlus,
    Trash2 as Trash,
    User,
  } from "lucide-svelte";

  let { id, type, ...props } = $props();

  let deleting = $state();
  let deletion = () => {
    deleting = true;

    let update = mutationStore({
      client: graphql,
      query: gql`
        mutation ($input: DeletionInput!) {
          deletion(input: $input) {
            errors
          }
        }
      `,
      variables: { input: { id, type } },
    });

    update.subscribe((r) => {
      errors = r?.data?.deletion?.errors;
      errors = errors?.length ? errors : null;
      deleting = r?.fetching;

      if (r?.data?.deletion) {
        deleted = !errors;
        deleting = false;
      }
    });
  };
</script>

{@render children({ deletion, deleting, deleted, errors })}
