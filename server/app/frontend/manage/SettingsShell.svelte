<script>
  import Link from "./ui/Link.svelte";

  let { current, identifier, onsignout, onunpair, children } = $props();

  const TABS = [
    ["/settings", "General"],
    ["/policies", "Policies"],
    ["/providers", "Providers"],
    ["/provisioning", "Provisioning"],
    ["/adapters", "Adapters"],
    ["/activity", "Activity"],
  ];

  function unpair() {
    if (confirm("Forget this manage client? masks asks you to approve a new one right away. The old client stays under Clients until it is archived.")) onunpair();
  }
</script>

<div class="settings">
  <aside class="settings-side">
    <nav class="settings-tabs" aria-label="Settings">
      {#each TABS as [to, label] (to)}
        <Link
          {to}
          class="settings-tab {current === to.slice(1) ? 'settings-tab-on' : ''}"
        >{label}</Link>
      {/each}
    </nav>

    <div class="settings-me">
      <span class="settings-who" title={identifier}>{identifier}</span>
      <button type="button" class="settings-tab" onclick={onsignout}>Sign out</button>
      <button type="button" class="settings-tab settings-quiet" onclick={unpair}>Forget client</button>
    </div>
  </aside>

  <div class="min-w-0">{@render children()}</div>
</div>
