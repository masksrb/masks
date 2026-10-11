<script>
  import { t } from "./lib/copy.js";
  import LdapSection from "./LdapSection.svelte";
  import ProvisioningSection from "./ProvisioningSection.svelte";
  import Page from "./ui/Page.svelte";

  let { api } = $props();
</script>

<Page title={t("directory.title")} lede={t("directory.lede")}>
  <div class="grid gap-4">
    <ProvisioningSection {api} />

    <LdapSection {api} />
  </div>
</Page>
