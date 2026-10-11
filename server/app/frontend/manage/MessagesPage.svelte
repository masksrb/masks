<script>
  import { t } from "./lib/copy.js";
  import MessageSending from "./MessageSending.svelte";
  import MessageTemplates from "./MessageTemplates.svelte";
  import Link from "./ui/Link.svelte";
  import Page from "./ui/Page.svelte";

  let { api, part = null } = $props();

  const templates = $derived(part === "templates");
</script>

<Page title={t("messages.title")} lede={t(templates ? "messages.templates.lede" : "messages.sending.lede")}>
  <nav class="settings-tabs" aria-label={t("messages.parts")}>
    <Link to="/messages" class="settings-tab {templates ? '' : 'settings-tab-on'}">{t("messages.sending.title")}</Link>
    <Link to="/messages/templates" class="settings-tab {templates ? 'settings-tab-on' : ''}">{t("messages.templates.title")}</Link>
  </nav>

  {#if templates}
    <MessageTemplates {api} />
  {:else}
    <MessageSending {api} />
  {/if}
</Page>
