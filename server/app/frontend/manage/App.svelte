<script>
  import { untrack } from "svelte";
  import { createApi } from "./lib/api.svelte.js";
  import { createRouter, provideRouter } from "./lib/router.svelte.js";
  import { handshakeUrl, redeem } from "./lib/pairing.js";
  import Link from "./ui/Link.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import ActorsPage from "./ActorsPage.svelte";
  import ActorPage from "./ActorPage.svelte";
  import DevicePage from "./DevicePage.svelte";
  import ClientsPage from "./ClientsPage.svelte";
  import ClientPage from "./ClientPage.svelte";
  import SettingsPage from "./SettingsPage.svelte";
  import ActivityPage from "./ActivityPage.svelte";
  import ProvidersPage from "./ProvidersPage.svelte";
  import AdaptersPage from "./AdaptersPage.svelte";
  import PoliciesPage from "./PoliciesPage.svelte";
  import ProvisioningPage from "./ProvisioningPage.svelte";
  import SettingsShell from "./SettingsShell.svelte";

  let { boot } = $props();

  const api = untrack(() => createApi(boot));
  const router = untrack(() => createRouter(boot.root));

  provideRouter(router);

  let phase = $state("starting");
  let failure = $state(null);
  let viewer = $state(null);

  const NAV = [
    ["", "Overview", '<path d="M3.5 10.5 10 4l6.5 6.5"/><path d="M5.5 9v7h9V9"/>'],
    ["/actors", "Actors", '<circle cx="10" cy="7" r="3"/><path d="M4 17c.8-3 3.2-4.5 6-4.5s5.2 1.5 6 4.5"/>'],
    ["/clients", "Clients", '<rect x="3" y="3" width="6" height="6" rx="1.5"/><rect x="11" y="3" width="6" height="6" rx="1.5"/><rect x="3" y="11" width="6" height="6" rx="1.5"/><rect x="11" y="11" width="6" height="6" rx="1.5"/>'],
  ];

  const SETTINGS = ["settings", "policies", "providers", "provisioning", "adapters", "activity"];

  function register() {
    location.replace(handshakeUrl(boot));
  }

  async function start() {
    const query = new URLSearchParams(location.search);

    try {
      if (query.get("error") === "invalid_client") {
        api.unpair();
        register();
        return;
      }

      if (query.get("error")) {
        failure = query.get("error_description") || query.get("error");
        router.replace("");
        phase = "failed";
        return;
      }

      if (query.get("initial_access_token")) {
        await redeem(boot, query.get("initial_access_token"));
        router.replace("");
        await api.authorize("");
        return;
      }

      if (!api.paired()) {
        register();
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
      phase = "failed";
    }
  }

  function ready() {
    phase = "ready";

    api
      .query("query Viewer { viewer { identifier avatars { photo identicon } } }")
      .then((data) => {
        viewer = data.viewer;
      })
      .catch(() => {});
  }

  start();

  const current = $derived(router.segments[0] ?? "");
  const inSettings = $derived(SETTINGS.includes(current));
  const signedInAs = $derived(
    viewer?.identifier ?? api.state.identity?.preferred_username ?? "Account",
  );

  function retry() {
    location.assign(boot.root);
  }

  function forget() {
    api.unpair();
    retry();
  }

  async function signOut() {
    location.assign((await api.signOut()) ?? boot.root);
  }
</script>

{#if phase === "starting"}
  <div class="grid min-h-screen place-items-center">
    <Spinner label="Starting" />
  </div>
{:else if phase === "failed"}
  <div class="auth-page">
    <main class="auth-col surface-terminus">
      <div class="flow">
        <span class="state state-bad">Stopped</span>

        <h1 class="prompt-title">Could not sign in to manage {boot.tenant.name}</h1>

        <p class="said">{failure}</p>

        <button type="button" class="action" onclick={retry}>Try again</button>
      </div>
    </main>
  </div>
{:else}
  <div class="flex min-h-screen flex-col">
    <header class="sticky top-0 z-20 border-b border-base-300 bg-base-100/95 backdrop-blur">
      <div class="mx-auto flex w-full max-w-6xl items-center gap-x-6 px-4 py-2">
        <Link to="" class="brand"><img src="/masks-public/icon.svg" alt="" class="brand-mark" />{boot.tenant.name}</Link>

        <nav class="nav md:flex-1">
          {#each NAV as [to, label] (to)}
            <Link
              {to}
              class="nav-item {current === to.replace('/', '') ? 'nav-item-on' : ''}"
            >{label}</Link>
          {/each}
        </nav>

        <Link
          to="/settings"
          class="console-me ms-auto {inSettings ? 'console-me-on' : ''}"
          aria-label="Settings, signed in as {signedInAs}"
          title={signedInAs}
        >
          {#if viewer}
            <img
              src={`${viewer.avatars.photo ?? viewer.avatars.identicon}?size=64`}
              width="32"
              height="32"
              alt=""
              class:drawn={!viewer.avatars.photo}
              onerror={(event) => (event.currentTarget.src = `${viewer.avatars.identicon}?size=64`)}
            />
          {:else}
            <span>{signedInAs.slice(0, 1).toUpperCase()}</span>
          {/if}
        </Link>
      </div>
    </header>

    <main class="console-main mx-auto w-full max-w-6xl flex-1 p-4 md:p-6">
      {#if current === ""}
        <SettingsPage {api} {boot} overview />
      {:else if current === "actors"}
        {#if router.segments[1] === "devices" && router.segments[2]}
          <DevicePage {api} id={router.segments[2]} />
        {:else if router.segments[1]}
          <ActorPage {api} uuid={router.segments[1]} />
        {:else}
          <ActorsPage {api} />
        {/if}
      {:else if current === "clients"}
        {#if router.segments[1]}
          <ClientPage {api} clientId={router.segments[1]} />
        {:else}
          <ClientsPage {api} />
        {/if}
      {:else if inSettings}
        <SettingsShell {current} identifier={signedInAs} onsignout={signOut} onunpair={forget}>
          {#if current === "providers"}
            <ProvidersPage {api} />
          {:else if current === "policies"}
            <PoliciesPage {api} />
          {:else if current === "provisioning"}
            <ProvisioningPage {api} />
          {:else if current === "adapters"}
            <AdaptersPage {api} />
          {:else if current === "activity"}
            <ActivityPage {api} />
          {:else}
            <SettingsPage {api} {boot} />
          {/if}
        </SettingsShell>
      {:else}
        <div class="rounded-box border border-base-300 bg-base-100 px-6 py-14 text-center">
          <p class="text-sm opacity-70">There is no page at this address.</p>
        </div>
      {/if}
    </main>

    <nav class="tabbar md:hidden" aria-label="Sections">
      {#each NAV as [to, label, icon] (to)}
        <Link {to} class="tabbar-item {current === to.replace('/', '') ? 'tabbar-item-on' : ''}">
          <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{@html icon}</svg>
          <span>{label}</span>
        </Link>
      {/each}
    </nav>
  </div>
{/if}
