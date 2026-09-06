<script>
  import { untrack } from "svelte";
  import { createApi } from "./lib/api.svelte.js";
  import { createRouter, provideRouter } from "./lib/router.svelte.js";
  import { redeem } from "./lib/pairing.js";
  import Link from "./ui/Link.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Pair from "./Pair.svelte";
  import PeoplePage from "./PeoplePage.svelte";
  import ActorPage from "./ActorPage.svelte";
  import ClientsPage from "./ClientsPage.svelte";
  import ClientPage from "./ClientPage.svelte";
  import SettingsPage from "./SettingsPage.svelte";
  import ActivityPage from "./ActivityPage.svelte";
  import ProvidersPage from "./ProvidersPage.svelte";

  let { boot } = $props();

  const api = untrack(() => createApi(boot));
  const router = untrack(() => createRouter(boot.root));

  provideRouter(router);

  let phase = $state("starting");
  let failure = $state(null);
  let viewer = $state(null);

  const NAV = [
    ["", "Overview"],
    ["/people", "People"],
    ["/clients", "Clients"],
    ["/providers", "Providers"],
    ["/activity", "Activity"],
    ["/settings", "Settings"],
  ];

  async function start() {
    const query = new URLSearchParams(location.search);

    try {
      if (query.get("error")) {
        if (query.get("error") === "invalid_client") api.unpair();

        failure = query.get("error_description") || query.get("error");
        phase = "pairing";
        return;
      }

      if (query.get("initial_access_token")) {
        await redeem(boot, query.get("initial_access_token"));
        router.replace("");
        await api.authorize("");
        return;
      }

      if (!api.paired()) {
        phase = "pairing";
        return;
      }

      if (router.segments[0] === "callback") {
        const { returnTo } = await api.callback();
        router.replace(returnTo || "");
        ready();
        return;
      }

      if (!api.signedIn()) {
        await api.authorize(router.state.path.slice(boot.root.length));
        return;
      }

      ready();
    } catch (thrown) {
      failure = thrown.message;
      phase = api.paired() ? "failed" : "pairing";
    }
  }

  function ready() {
    phase = "ready";

    api
      .query("query Viewer { viewer { nickname } }")
      .then((data) => {
        viewer = data.viewer;
      })
      .catch(() => {});
  }

  start();

  const current = $derived(router.segments[0] ?? "");
  const signedInAs = $derived(
    viewer?.nickname ?? api.state.identity?.preferred_username ?? "Account",
  );

  function repair() {
    api.unpair();
    location.assign(boot.root);
  }

  async function signOut() {
    location.assign((await api.signOut()) ?? boot.root);
  }
</script>

{#if phase === "pairing"}
  <Pair {boot} {failure} />
{:else if phase === "starting"}
  <div class="grid min-h-screen place-items-center">
    <Spinner label="Starting" />
  </div>
{:else if phase === "failed"}
  <div class="auth-page">
    <main class="auth-col surface-terminus">
      <div class="flow">
        <span class="state state-bad">Stopped</span>

        <h1 class="prompt-title">This console could not start</h1>

        <p class="said">{failure}</p>

        <p class="prompt-lede">
          Its registration may have been archived. Pairing again registers this browser from
          scratch.
        </p>

        <button type="button" class="action" onclick={repair}>Pair again</button>
      </div>
    </main>
  </div>
{:else}
  <div class="flex min-h-screen flex-col">
    <header class="sticky top-0 z-20 border-b border-base-300 bg-base-100/95 backdrop-blur">
      <div class="mx-auto flex w-full max-w-6xl flex-wrap items-center gap-x-6 gap-y-2 px-4 py-2">
        <Link to="" class="brand">{boot.tenant.name}</Link>

        <nav class="nav order-3 w-full md:order-none md:w-auto md:flex-1">
          {#each NAV as [to, label] (to)}
            <Link
              {to}
              class="nav-item {current === to.replace('/', '') ? 'nav-item-on' : ''}"
            >{label}</Link>
          {/each}
        </nav>

        <div class="dropdown dropdown-end ms-auto md:ms-0">
          <div tabindex="0" role="button" class="btn btn-ghost btn-sm gap-2">
            {signedInAs}
            <span class="opacity-50">&#9662;</span>
          </div>
          <ul class="dropdown-content menu z-30 w-60 gap-1 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg">
            <li><button type="button" onclick={signOut}>Sign out</button></li>
            <li>
              <button type="button" onclick={repair}>
                Unpair this browser
                <span class="text-xs opacity-60">Forgets the registration</span>
              </button>
            </li>
          </ul>
        </div>
      </div>
    </header>

    <main class="mx-auto w-full max-w-6xl flex-1 p-4 md:p-6">
      {#if current === ""}
        <SettingsPage {api} {boot} overview />
      {:else if current === "people"}
        {#if router.segments[1]}
          <ActorPage {api} uuid={router.segments[1]} />
        {:else}
          <PeoplePage {api} />
        {/if}
      {:else if current === "clients"}
        {#if router.segments[1]}
          <ClientPage {api} clientId={router.segments[1]} />
        {:else}
          <ClientsPage {api} />
        {/if}
      {:else if current === "providers"}
        <ProvidersPage {api} />
      {:else if current === "activity"}
        <ActivityPage {api} />
      {:else if current === "settings"}
        <SettingsPage {api} {boot} />
      {:else}
        <div class="rounded-box border border-base-300 bg-base-100 px-6 py-14 text-center">
          <p class="text-sm opacity-70">There is no page at this address.</p>
        </div>
      {/if}
    </main>
  </div>
{/if}
