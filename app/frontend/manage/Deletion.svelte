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
  import {
    mutationStore,
    queryStore,
    gql,
    getContextClient,
  } from "@urql/svelte";

  let { id, type, children, ...props } = $props();

  let deleting = $state();
  let deleted = $state();
  let errors = $state();
  let client = getContextClient();
  let deletion = () => {
    if (props.confirm && !confirm(props.confirm)) {
      return;
    }

    deleting = true;

    let update = mutationStore({
      client,
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

      if (deleted && props.ondelete) {
        props.ondelete();
      }

      if (deleted && props.reload) {
        window.location.reload();
      }
    });
  };
</script>

{@render children({ deletion, deleting, deleted, errors })}
