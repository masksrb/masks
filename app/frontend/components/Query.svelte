<script>
  import Error from "./Error.svelte";
  import { copy } from "svelte-copy";
  import _ from "lodash-es";
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

  let { key, children, ...props } = $props();

  let loading = $state(true);
  let error = $state();
  let variables = $state();
  let query = $derived(
    queryStore({
      client: getContextClient(),
      pause: !variables || props.result,
      query: props.query,
      variables,
      requestPolicy: "network-only",
    })
  );

  let result = $state(props.result || []);
  let subscribe = (vars) => {
    if (vars) {
      variables = vars;
    }

    query.subscribe((r) => {
      result = key ? _.get(r?.data || {}, key, []) : r?.data;
      loading = !r?.data;
      error = r?.error;
    });

    query.resume();
  };

  if (props.variables || props.autoquery) {
    subscribe(props.variables);
  }
</script>

{@render children({ result, loading, error, refresh: subscribe })}

{#if error}
  <Error {error} />
{/if}
