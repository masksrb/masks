<script>
  import {
    Client,
    setContextClient,
    cacheExchange,
    fetchExchange,
  } from "@urql/svelte";
  import { onMount, setContext } from "svelte";

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

  const graphql = new Client({
    url: `/login.graphql${window.location.search}`,
    exchanges: [cacheExchange, fetchExchange],
    fetchOptions: () => {
      return {
        headers: { "X-CSRF-Token": csrf },
      };
    },
  });

  setContext("page", {
    csrf,
    graphql,
    fetch: (url, options) => {
      return fetch(url, fetchOptions(csrf, options));
    },
  });

  setContextClient(graphql);

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
