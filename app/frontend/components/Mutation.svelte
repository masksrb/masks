<script>
  import _ from "lodash-es";
  import ErrorMessage from "./Error.svelte";
  import { mutationStore, getContextClient } from "@urql/svelte";

  let { key, input, query, children, ...props } = $props();

  let mutating = $state();
  let client = getContextClient();
  let mutate = (vars) => {
    let extras = vars.preventDefault && vars.stopPropagation ? {} : vars;
    let variables = {
      input: { ...input, ...extras },
    };

    if (props.confirm && !confirm(props.confirm)) {
      return;
    }

    mutating = true;

    let update = mutationStore({
      client,
      query,
      variables,
    });

    update.subscribe((r) => {
      if (r?.data && _.get(r.data, key)) {
        props?.onmutate?.(_.get(r.data, key));
        mutating = false;
      }

      if (r?.error) {
        error = r?.error;
      }
    });
  };

  let modal;
  let error = $state();
</script>

{@render children({ mutating, mutate })}

{#if error}
  <ErrorMessage {error} />
{/if}
