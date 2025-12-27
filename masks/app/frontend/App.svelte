<script>
import { setContextClient } from "@urql/svelte";
import { onMount, setContext } from "svelte";
import { Consumer } from "@/lib";

let csrf = document.querySelector('meta[name="csrf-token"]').content;

let { Component, component, ...props } = $props();

let masks = new Consumer({ csrf, graphql: props.graphql });

setContext("page", {
  root: props.root,
  url: props.url,
  csrf,
  masks,
});

setContextClient(masks.graphql);

let Page = $state();

onMount(async () => {
  if (Component) {
    Page = Component;
  } else if (component) {
    Page = (await component()).default;
  }
});
</script>

<Page {...props} />
