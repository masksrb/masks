<script>
  import _ from "lodash-es";
  import { route } from "@mateothegreat/svelte5-router";
  import Time from "@/components/Time.svelte";
  import Avatar from "../components/Avatar.svelte";
  import AddPage from "./AddPage.svelte";
  import ActorResult from "./ActorResult.svelte";
  import ClientResult from "./ClientResult.svelte";
  import Query from "@/components/Query.svelte";
  import { gql } from "@urql/svelte";
  import { Home, User, ServerCog, X, Search, EyeOff, Eye } from "lucide-svelte";
  import TokenResult from "./TokenResult.svelte";
  import ProviderResult from "./ProviderResult.svelte";
  import { getContext, onMount } from "svelte";

  /**
   * @typedef {Object} Props
   * @property {any} actor
   * @property {string} [url]
   */

  /** @type {Props} */
  let {
    actor,
    url = "",
    loading = false,
    notFound = false,
    children,
    ...props
  } = $props();
  let page = getContext("page");
  let { root, masks } = page;
  let input = $state();
  let variables = $state({ input: "" });

  let query = gql`
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
          createdAt
          updatedAt
        }
        providers {
          id
          name
          type
        }
        tokens {
          id
          type
          name
          secret
          usable
          expired
          revokedAt
          expiresAt
        }
      }
    }
  `;

  let isSearching = $state();

  let toggleSearch = (current) => {
    return (e) => {
      e?.preventDefault?.();
      e?.stopPropagation?.();

      isSearching = !current;
    };
  };

  let openSearch = () => {
    isSearching = true;
  };

  let showSecrets = $state(localStorage.getItem("masks.show-secrets"));
  let countdown = $state();

  let updateSecrets = () => {
    let value = localStorage.getItem("masks.show-secrets");

    let remaining = Number.parseInt(
      Math.max(0, Number.parseInt(value || "0") - Date.now() / 1000)
    );

    if (remaining > 0) {
      countdown = remaining;
      showSecrets = page.showSecrets = true;
    } else {
      showSecrets = page.showSecrets = false;
      countdown = null;
    }

    masks.setHeaders(showSecrets ? { "X-Show-Secrets": "true" } : {});
  };

  onMount(() => {
    updateSecrets();

    let interval = setInterval(updateSecrets, 1000);

    return () => {
      clearInterval(interval);
    };
  });

  let toggleSecrets = () => {
    let timeout = 1; // minutes

    showSecrets = !showSecrets;

    if (showSecrets) {
      localStorage.setItem(
        "masks.show-secrets",
        Date.now() / 1000 + timeout * 60
      );
    } else {
      localStorage.removeItem("masks.show-secrets");
      countdown = null;
    }

    updateSecrets();
  };

  let blurSearch = () => {
    if (!input) {
      closeSearch();
    }
  };

  let closeSearch = () => {
    isSearching = false;
    input = "";
  };

  let handleKey = (e) => {
    if (e.key == "Escape" || (e.key == "Backspace" && !input)) {
      e.preventDefault();
      e.stopPropagation();

      closeSearch();
    }
  };

  let debounceInput = (refresh) => {
    return _.debounce((e) => {
      isSearching = true;

      if (!e.target.value) {
        return;
      }

      variables = { input: e.target.value };

      refresh(variables);
    }, 300);
  };

  let isEmpty = (search) => {
    return (
      search &&
      !search.actors?.length &&
      !search.clients?.length &&
      !search.tokens?.length &&
      !search.providers?.length
    );
  };
</script>

<Query {query} variables={!input ? null : variables} key="search">
  {#snippet children({ result, refresh })}
    <div
      class={`bg-base-300 h-full group ${isSearching ? "is-searching" : ""}`}
    >
      <div>
        <div class="navbar bg-base-200 my-0 min-h-0">
          <div
            class="navbar-start group-[.is-searching]:hidden md:group-[.is-searching]:flex gap-3"
          >
            <div class="cols-1.5">
              <ul class="menu menu-horizontal menu-sm p-0">
                <li>
                  <details>
                    <summary>
                      <span class="w-[30px] h-[30px] -ml-1.5">
                        <Avatar {actor} />
                      </span>

                      <span class="text-lg font-bold dark:text-white text-black"
                        >masks</span
                      >
                    </summary>

                    <ul
                      class="bg-base-100 rounded-t-none p-2 whitespace-nowrap z-100 -ml-1.5"
                    >
                      <li class="rows menu-title text-base-content">
                        {actor.identifier}

                        <span
                          class="label-xs whitespace-nowrap menu-title !m-0 !p-0"
                          >last login <Time
                            relative
                            timestamp={actor.lastLoginAt}
                            class="whitespace-nowrap italic"
                          /></span
                        >
                        <span class="divider my-0 mt-1.5 mx-0"></span>
                      </li>
                      <li>
                        <a class="whitespace-nowrap cols-3" href={root}
                          ><Home class="opacity-50" size="12" />Go home</a
                        >
                      </li>
                      <li>
                        <a class="whitespace-nowrap cols-3" href={props.profile}
                          ><User class="opacity-50" size="12" />Your profile</a
                        >
                      </li>
                      <li>
                        <button
                          type="button"
                          tabindex="0"
                          onclick={toggleSecrets}
                          class={`whitespace-nowrap cols-3`}
                        >
                          {#if showSecrets}
                            <Eye size="12" class="text-warning" />

                            Hide secrets
                          {:else}
                            <EyeOff size="12" class="opacity-50" />

                            Show secrets
                          {/if}
                        </button>
                      </li>
                      <li>
                        <a
                          class="whitespace-nowrap cols-3"
                          href={`${root}/settings`}
                          ><ServerCog class="opacity-50" size="12" />
                          Settings</a
                        >
                      </li>
                    </ul>
                  </details>
                </li>
              </ul>

              {#if showSecrets}
                <button
                  type="button"
                  tabindex="0"
                  onclick={toggleSecrets}
                  class={`btn btn-xs rounded-full btn-neutral btn-warning`}
                >
                  <Eye size="14" />

                  {#if countdown}
                    <span class="label-xs font-bold -ml-1 text-warning-content">
                      {countdown}s
                    </span>
                  {/if}
                </button>
              {/if}
            </div>
          </div>

          <div class="flex items-center join grow w-full">
            <label
              class="input input-sm input-ghost items-center gap-3 grow w-full
                join-item hidden md:flex group-[.is-searching]:flex"
            >
              <div class="w-6 h-6 opacity-50">
                {#if loading}
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
                oninput={debounceInput(refresh)}
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
                {#if isSearching}
                  <X size="20" />
                {:else}
                  <Search size="20" />
                {/if}
              </button>

              <AddPage />
            </div>
          </div>
        </div>

        <div
          class={`w-full grow ${input && isSearching ? "animate-fade-in-fast" : "hidden"}`}
        >
          <div
            class="z-50 absolute w-full shadow-xl dark:bg-black bg-neutral left-0 right-0 top-[48px] p-3 shadow-inner"
          >
            {#if isEmpty(result)}
              <div
                class="rounded-lg border-dashed border-2 border-base-300 p-6"
              >
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
                      <a use:route href={`${root}/actor/${actor.id}`}>
                        <ActorResult {actor} class="bg-base-300" disabled />
                      </a>
                    {/each}
                  {/if}

                  {#if result?.clients?.length}
                    <div class="mb-1.5 mt-3 pl-3 font-bold text-xs uppercase">
                      clients
                    </div>
                    {#each result.clients as client (client.id)}
                      <a href={`${root}/client/${client.id}`}>
                        <ClientResult {client} class="bg-base-200" disabled />
                      </a>
                    {/each}
                  {/if}

                  {#if result?.providers?.length}
                    <div class="mb-1.5 mt-3 pl-3 font-bold text-xs uppercase">
                      providers
                    </div>
                    {#each result.providers as provider (provider.id)}
                      <ProviderResult {provider} link />
                    {/each}
                  {/if}

                  {#if result?.tokens?.length}
                    <div class="mb-1.5 mt-3 pl-3 font-bold text-xs uppercase">
                      tokens
                    </div>
                    {#each result.tokens as token (token.id)}
                      <TokenResult {token} link />
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

            <h2 class="text-lg">
              The page you're looking for could not be found.
            </h2>
          </div>
        {:else if loading}
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
  {/snippet}
</Query>
