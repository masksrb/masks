<script>
  import { t } from "./lib/copy.js";
  import MessageSending from "./MessageSending.svelte";
  import MessageWording from "./MessageWording.svelte";
  import Link from "./ui/Link.svelte";
  import Page from "./ui/Page.svelte";

  let { api, part = null } = $props();

  const wording = $derived(part === "wording");
</script>

<Page title={t("messages.title")} lede={t(wording ? "messages.wording.lede" : "messages.sending.lede")}>
  <nav class="settings-tabs" aria-label={t("messages.parts")}>
    <Link to="/messages" class="settings-tab {wording ? '' : 'settings-tab-on'}">{t("messages.sending.title")}</Link>
    <Link to="/messages/wording" class="settings-tab {wording ? 'settings-tab-on' : ''}">{t("messages.wording.title")}</Link>
  </nav>

  {#if wording}
    <MessageWording {api} />
  {:else}
    <MessageSending {api} />
  {/if}
</Page>
