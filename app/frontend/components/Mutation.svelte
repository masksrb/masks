<script>
  import _ from "lodash-es";
  import ErrorMessage from "./Error.svelte";
  import { mutationStore, getContextClient } from "@urql/svelte";

  let { key, input, query, children, ...props } = $props();

  let mutating = $state();
  let client = getContextClient();
  let mutate = (vars, { merge = true, confirm = false } = {}) => {
    let extras =
      vars?.preventDefault && vars?.stopPropagation ? {} : vars || {};
    let variables = merge
      ? {
          input: { ...input, ...extras },
        }
      : { input: { ...extras } };

    if (
      (confirm || props.confirm) &&
      !window.confirm(confirm || props.confirm)
    ) {
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

  let error = $state();

  if (props.autorun) {
    mutate();
  }
</script>

{@render children({ mutating, mutate })}

{#if error}
  <ErrorMessage {error} />
{/if}
