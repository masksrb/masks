<script>
  import { t } from "./lib/copy.js";
  import Link from "./ui/Link.svelte";

  let { current, viewer, identifier, account, onsignout, onunpair, children } = $props();

  const TABS = ["settings", "groups", "policies", "providers", "domains", "provisioning", "ldap", "adapters", "streams", "email", "activity"];

  function unpair() {
    if (confirm(t("settings_shell.forget_confirm"))) onunpair();
  }
</script>

<div class="settings">
  <div class="settings-bar">
    <nav class="settings-tabs" aria-label={t("settings_shell.label")}>
      {#each TABS as tab (tab)}
        <Link
          to={`/${tab}`}
          class="settings-tab {current === tab ? 'settings-tab-on' : ''}"
        >{t(`settings_shell.tabs.${tab}`)}</Link>
      {/each}
    </nav>

    <div class="settings-me">
      <a class="settings-who" href={account} title={t("settings_shell.account")}>
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
      <button type="button" class="settings-tab" onclick={onsignout}>{t("settings_shell.sign_out")}</button>
      <button type="button" class="settings-tab settings-quiet" onclick={unpair}>{t("settings_shell.forget")}</button>
    </div>
  </div>

  <div class="min-w-0">{@render children()}</div>
</div>
