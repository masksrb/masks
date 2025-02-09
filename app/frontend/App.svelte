<script>
  import {
    Client,
    setContextClient,
    cacheExchange,
    fetchExchange,
  } from "@urql/svelte";
  import { onMount, getContext, setContext } from "svelte";

  import { Consumer } from "@/lib";

  let csrf = document.querySelector('meta[name="csrf-token"]').content;

  function fetchOptions(csrf, options) {
    const update = { ...options };

    update.headers = {
      ...update.headers,
      "X-CSRF-Token": csrf,
    };

    return update;
  }

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
