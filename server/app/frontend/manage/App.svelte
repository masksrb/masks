<script>
  import { untrack } from "svelte";
  import { createApi } from "./lib/api.svelte.js";
  import { createRouter } from "./lib/router.svelte.js";
  import { redeem } from "./lib/pairing.js";
  import Pair from "./Pair.svelte";
  import ActorsPage from "./ActorsPage.svelte";
  import ActorPage from "./ActorPage.svelte";
  import ClientsPage from "./ClientsPage.svelte";
  import ClientPage from "./ClientPage.svelte";
  import SessionsPage from "./SessionsPage.svelte";
  import SettingsPage from "./SettingsPage.svelte";

  let { boot } = $props();

  const api = untrack(() => createApi(boot));
  const router = untrack(() => createRouter(boot.root));

  let phase = $state("starting");
  let failure = $state(null);

  const NAV = [
    ["", "Overview"],
    ["/actors", "Actors"],
    ["/clients", "Clients"],
    ["/sessions", "Sessions"],
    ["/settings", "Settings"],
  ];

  async function start() {
    const query = new URLSearchParams(location.search);

    try {
      if (query.get("error")) {
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
        phase = "ready";
        return;
      }

      if (!api.signedIn()) {
        await api.authorize(router.state.path.slice(boot.root.length));
        return;
      }

      phase = "ready";
    } catch (thrown) {
      failure = thrown.message;
      phase = api.paired() ? "failed" : "pairing";
    }
  }

  start();

  const current = $derived(router.segments[0] ?? "");

  function repair() {
    api.unpair();
    location.assign(boot.root);
  }
</script>

{#if phase === "pairing"}
  <Pair {boot} {failure} />
{:else if phase === "starting"}
  <div class="min-h-screen grid place-items-center">
    <span class="loading loading-spinner loading-lg"></span>
  </div>
{:else if phase === "failed"}
  <div class="min-h-screen grid place-items-center p-4">
    <div class="card bg-base-100 shadow-xl max-w-lg w-full">
      <div class="card-body gap-4">
        <h1 class="card-title">This admin app could not start</h1>
        <div class="alert alert-error text-sm" role="alert">{failure}</div>
        <button class="btn" onclick={repair}>Forget this registration and pair again</button>
      </div>
    </div>
  </div>
{:else}
  <div class="min-h-screen flex flex-col">
    <header class="navbar bg-base-100 border-b border-base-content/10 px-4 gap-4">
      <a class="font-bold" href={boot.root} onclick={(e) => { e.preventDefault(); router.go(""); }}>
        {boot.tenant.name}
      </a>

      <nav class="tabs tabs-border flex-1">
        {#each NAV as [to, label] (to)}
          <button
            class="tab"
            class:tab-active={current === to.slice(1) || (to === "" && current === "")}
            onclick={() => router.go(to)}
          >{label}</button>
        {/each}
      </nav>

      <div class="dropdown dropdown-end">
        <div tabindex="0" role="button" class="btn btn-ghost btn-sm">
          {api.state.identity?.preferred_username ?? "signed in"}
        </div>
        <ul class="dropdown-content menu bg-base-100 rounded-box shadow z-10 w-56 p-2">
          <li><button onclick={() => { api.signOut(); location.assign(boot.root); }}>Sign out</button></li>
          <li><button onclick={repair}>Forget this registration</button></li>
        </ul>
      </div>
    </header>

    <main class="flex-1 p-4 md:p-6 max-w-6xl w-full mx-auto">
      {#if current === ""}
        <SettingsPage {api} {boot} overview />
      {:else if current === "actors"}
        {#if router.segments[1]}
          <ActorPage {api} uuid={router.segments[1]} {router} />
        {:else}
          <ActorsPage {api} {router} />
        {/if}
      {:else if current === "clients"}
        {#if router.segments[1]}
          <ClientPage {api} clientId={router.segments[1]} {router} />
        {:else}
          <ClientsPage {api} {router} />
        {/if}
      {:else if current === "sessions"}
        <SessionsPage {api} />
      {:else if current === "settings"}
        <SettingsPage {api} {boot} />
      {:else}
        <p class="opacity-70">Nothing here.</p>
      {/if}
    </main>
  </div>
{/if}
