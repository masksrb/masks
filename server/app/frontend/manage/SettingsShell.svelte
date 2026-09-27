<script>
  import Link from "./ui/Link.svelte";

  let { current, viewer, identifier, account, onsignout, onunpair, children } = $props();

  const TABS = [
    ["/settings", "General"],
    ["/policies", "Policies"],
    ["/providers", "Providers"],
    ["/provisioning", "Provisioning"],
    ["/adapters", "Adapters"],
    ["/streams", "Streams"],
    ["/email", "Email"],
    ["/activity", "Activity"],
  ];

  function unpair() {
    if (confirm("Forget this manage client? masks asks you to approve a new one right away. The old client stays under Clients until it is archived.")) onunpair();
  }
</script>

<div class="settings">
  <div class="settings-bar">
    <nav class="settings-tabs" aria-label="Settings">
      {#each TABS as [to, label] (to)}
        <Link
          {to}
          class="settings-tab {current === to.slice(1) ? 'settings-tab-on' : ''}"
        >{label}</Link>
      {/each}
    </nav>

    <div class="settings-me">
      <a class="settings-who" href={account} title="Your account">
        {#if viewer}
          <img
            src={`${viewer.avatars.photo ?? viewer.avatars.identicon}?size=64`}
            width="24"
            height="24"
            alt=""
            class:drawn={!viewer.avatars.photo}
            onerror={(event) => (event.currentTarget.src = `${viewer.avatars.identicon}?size=64`)}
          />
        {/if}
        <span>{identifier}</span>
      </a>
      <button type="button" class="settings-tab" onclick={onsignout}>Sign out</button>
      <button type="button" class="settings-tab settings-quiet" onclick={unpair}>Forget client</button>
    </div>
  </div>

  <div class="min-w-0">{@render children()}</div>
</div>
