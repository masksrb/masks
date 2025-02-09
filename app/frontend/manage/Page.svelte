<script>
  import { route } from "@mateothegreat/svelte5-router";
  import Avatar from "../components/Avatar.svelte";
  import AddPage from "./AddPage.svelte";
  import ActorResult from "./ActorResult.svelte";
  import ClientResult from "./ClientResult.svelte";
  import { queryStore, gql, getContextClient } from "@urql/svelte";
  import { ServerCog, X, Search } from "lucide-svelte";
  import _ from "lodash-es";

  /**
   * @typedef {Object} Props
   * @property {any} actor
   * @property {string} [url]
   */

  /** @type {Props} */
  let {
    actor,
    children,
    install,
    url = "",
    loading = false,
    notFound = false,
  } = $props();
  let isAddOpen = $state();
  let input = $state();
  let variables = $state({ input: "" });
  let result = $state();
  let isLoading = $state();
  let query = $derived(
    queryStore({
      client: getContextClient(),
      query: gql`
        query ($input: String!) {
          search(query: $input) {
            actors {
              id
              name
              identifier
              identiconId
              avatar
              lastLoginAt
              createdAt
            }
            clients {
              id
              name
              type
              logo
              bgLight
              bgDark
              redirectUris
              createdAt
              updatedAt
            }
          }
        }
      `,
      variables,
      requestPolicy: "network-only",
    })
  );

  let isSearching = $state();

  let toggleSearch = (current) => {
    return () => {
      isSearching = !current;
      isAddOpen = false;
    };
  };

  let openSearch = () => {
    isSearching = true;
    isAddOpen = false;
  };

  let blurSearch = () => {
    if (!input) {
      closeSearch();
    }
  };

  let closeSearch = () => {
    isSearching = false;
    isAddOpen = false;
  };

  let handleKey = (e) => {
    if (e.key == "Escape" || (e.key == "Backspace" && !input)) {
      e.preventDefault();
      e.stopPropagation();

      closeSearch();
    }
  };

  let debounceInput = _.debounce((e) => {
    isSearching = true;

    if (!e.target.value) {
      return;
    }

    isLoading = true;
    variables = { input: e.target.value };

    query.subscribe(searchResponse);
  }, 300);

  let isOneOf = (search) => {
    return search?.actors?.length == 1 || search?.clients?.length == 1;
  };

  let isEmpty = (search) => {
    return search && !search.actors?.length && !search.clients?.length;
  };

  let searchResponse = (response) => {
    isLoading = !response?.data || response?.fetching;

    if (response?.data?.search) {
      result = response?.data?.search;
    }
  };

  let navbar;
</script>

<div class={`bg-base-300 h-full group ${isSearching ? "is-searching" : ""}`}>
  <div bind:this={navbar}>
    <div class="navbar bg-base-200 my-0 min-h-0">
      <div
        class="navbar-start group-[.is-searching]:hidden md:group-[.is-searching]:flex"
      >
        <div class="text-lg font-bold ml-4 text-white">
          <a use:route href={"/manage"}>masks</a>
        </div>
      </div>

      <div class="flex items-center join grow w-full">
        <label
          class="input input-sm input-ghost items-center gap-3 grow w-full
                join-item hidden md:flex group-[.is-searching]:flex"
        >
          <div class="w-6 h-6 opacity-50">
            {#if isLoading}
              <span class="loading loading-spinner"></span>
            {:else}
              <Search size="24" />
            {/if}
          </div>

          <input
            type="text"
            class="grow w-full placeholder:opacity-75"
            placeholder="search..."
            bind:value={input}
            oninput={debounceInput}
            onfocus={openSearch}
            onblur={blurSearch}
            onkeydown={handleKey}
          />

          {#if isSearching}
            <button
              type="button"
              tabindex="0"
              onclick={closeSearch}
              class={`btn btn-xs px-0 w-6 py-0 -mr-1.5`}
            >
              <X size="20" />
            </button>
          {/if}
        </label>
      </div>

      <div
        class="navbar-end pr-3 flex items-center gap-1 group-[.is-searching]:hidden md:group-[.is-searching]:flex"
      >
        <div class={`flex items-center gap-1`}>
          <button
            type="button"
            tabindex="0"
            onclick={toggleSearch(isSearching)}
            class={`btn btn-sm px-0 w-8 py-0 md:hidden`}
          >
            {#if isAddOpen}
              <X size="20" />
            {:else}
              <Search size="20" />
            {/if}
          </button>

          <AddPage />

          <a use:route href={"/manage/settings"}>
            <p
              class={`btn btn-sm btn-ghost px-0 w-8 ${
                install?.needsRestart ? "text-warning" : ""
              } relative`}
            >
              <ServerCog size="20" />
            </p>
          </a>
        </div>

        <a
          use:route
          href={`/manage/actor/${actor.id}`}
          class="w-[31px] h-[31px] ml-1.5"
        >
          <Avatar {actor} />
        </a>
      </div>
    </div>

    <div
      class={`w-full grow ${input && isSearching ? "animate-fade-in-fast" : "hidden"}`}
    >
      <div
        class="z-50 absolute w-full shadow-xl bg-base-100 left-0 right-0 top-[48px] p-3 shadow-inner"
      >
        {#if isEmpty(result)}
          <div class="rounded-lg border-dashed border-2 border-base-300 p-6">
            nothing found
          </div>
        {:else}
          <div class="flex flex-col gap-1.5">
            {#key input}
              {#if result?.actors?.length}
                <div class="mb-1.5 mt-3 pl-3 font-bold text-xs uppercase">
                  actors
                </div>
                {#each result.actors as actor (actor.id)}
                  <a use:route href={`/manage/actor/${actor.id}`}>
                    <ActorResult {actor} class="bg-base-300" disabled />
                  </a>
                {/each}
              {/if}

              {#if result?.clients?.length}
                <div class="mb-1.5 mt-3 pl-3 font-bold text-xs uppercase">
                  clients
                </div>
                {#each result.clients as client (client.id)}
                  <a href={`/manage/client/${client.id}`}>
                    <ClientResult {client} class="bg-base-200" disabled />
                  </a>
                {/each}
              {/if}
            {/key}
          </div>
        {/if}
      </div>
    </div>
  </div>

  <div class={`bg-base-300 text-base-content shadow-inner p-3 md:p-6 mb-6`}>
    {#if notFound}
      <div class="bold bg-base-300 rounded-lg w-prose mx-auto p-10">
        <h1 class="text-error text-2xl font-bold">Not found</h1>

        <h2 class="text-lg">The page you're looking for could not be found.</h2>
      </div>
    {:else if isLoading || loading}
      <div class="flex flex-col gap-4">
        <div class="flex items-center gap-4">
          <div class="skeleton h-16 w-16 shrink-0 rounded-lg"></div>
          <div class="flex flex-col gap-4 grow">
            <div class="skeleton h-4 w-1/2"></div>
            <div class="skeleton h-4 w-2/3"></div>
          </div>
        </div>
        <div class="skeleton h-4 w-full"></div>
        <div class="skeleton h-8 w-full"></div>
      </div>
    {:else}
      <div class="max-w-[850px] mx-auto">
        {@render children?.()}
      </div>
    {/if}
  </div>
</div>
