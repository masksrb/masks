<script>
  import { t } from "./lib/copy.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { since } from "./lib/format.js";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Switch from "./ui/Switch.svelte";

  let { api } = $props();

  const QUERY = `
    query Ldap {
      ldapBaseDn
      ldapPort
      ldapTls
      ldapCredentials { id label bindDn usedAt createdAt issuedBy { identifier } }
      tenant { ldapEnabled ldapPasswordOnly }
    }
  `;

  const feedback = createFeedback();

  let data = $state(null);
  let loading = $state(true);
  let label = $state("");
  let issued = $state(null);

  async function load() {
    loading = true;

    try {
      data = await api.query(QUERY);
    } catch (thrown) {
      feedback.blame(thrown);
    } finally {
      loading = false;
    }
  }

  load();

  async function issue() {
    const done = await feedback.attempt(() =>
      api.query(
        `mutation Issue($label: String!) {
          issueLdapCredential(label: $label) { secret ldapCredential { bindDn } }
        }`,
        { label: label.trim() },
      ),
    );

    if (!done) return;

    issued = done.issueLdapCredential;
    label = "";

    await load();
  }

  async function revoke(credential) {
    if (!confirm(t("ldap.revoke_confirm", { label: credential.label }))) return;

    const done = await feedback.attempt(
      () =>
        api.query(`mutation Revoke($id: ID!) { revokeLdapCredential(id: $id) { ldapCredential { id } } }`, {
          id: credential.id,
        }),
      t("ldap.revoked", { label: credential.label }),
    );

    if (done) await load();
  }

  async function serve(ldapEnabled) {
    const done = await feedback.attempt(
      () =>
        api.query(
          `mutation Serve($ldapEnabled: Boolean) {
            updateTenant(ldapEnabled: $ldapEnabled) { tenant { ldapEnabled } }
          }`,
          { ldapEnabled },
        ),
      t("ldap.serve.updated"),
    );

    if (done) await load();
  }

  async function passwordOnly(ldapPasswordOnly) {
    const done = await feedback.attempt(
      () =>
        api.query(
          `mutation PasswordOnly($ldapPasswordOnly: Boolean) {
            updateTenant(ldapPasswordOnly: $ldapPasswordOnly) { tenant { ldapPasswordOnly } }
          }`,
          { ldapPasswordOnly },
        ),
      t("ldap.binds.updated"),
    );

    if (done) await load();
  }
</script>

<Page title={t("ldap.title")} lede={t("ldap.lede")}>
  <Notices feedback={feedback.state} />

  {#if loading && !data}
    <Spinner />
  {:else if data}
    <div class="grid gap-4">
      <Section row title={t("ldap.serve.title")} help={t("ldap.serve.help")}>
        <Switch label={t("ldap.serve.on")} checked={data.tenant.ldapEnabled} onchange={serve} />
      </Section>

      <Section row title={t("ldap.connect.title")} help={t("ldap.connect.help")}>
        <div class="flex flex-col gap-1.5">
          <span class="field-label">{t("ldap.connect.address")}</span>
          <code class="tray px-2 py-1 font-mono text-xs break-all">
            {t(data.ldapTls ? "ldap.connect.ldaps" : "ldap.connect.port", { port: data.ldapPort })}
          </code>
        </div>

        <div class="flex flex-col gap-1.5">
          <span class="field-label">{t("ldap.connect.base_dn")}</span>
          <code class="tray px-2 py-1 font-mono text-xs break-all">{data.ldapBaseDn}</code>
        </div>

        <Field label={t("ldap.connect.label")} bind:value={label} placeholder="jellyfin" />

        <button type="button" class="btn btn-primary btn-sm self-start" disabled={!label.trim()} onclick={issue}>
          {t("ldap.connect.issue")}
        </button>

        {#if issued}
          <div class="alert alert-warning alert-soft flex-col items-start gap-2" role="status">
            <span class="font-medium">{t("ldap.connect.shown_once")}</span>
            <span class="text-xs">{t("ldap.connect.bind_dn")}</span>
            <code class="font-mono text-xs break-all">{issued.ldapCredential.bindDn}</code>
            <span class="text-xs">{t("ldap.connect.secret")}</span>
            <code class="font-mono text-xs break-all">{issued.secret}</code>
          </div>
        {/if}
      </Section>

      <Section row title={t("ldap.credentials.title")}>
        {#if data.ldapCredentials.length === 0}
          <p class="text-sm opacity-85">{t("ldap.credentials.none")}</p>
        {:else}
          <ul class="flex flex-col divide-y divide-base-200">
            {#each data.ldapCredentials as credential (credential.id)}
              <li class="flex flex-wrap items-center justify-between gap-2 py-2">
                <div class="min-w-0">
                  <div class="text-sm font-medium">{credential.label}</div>
                  <code class="font-mono text-xs break-all opacity-80">{credential.bindDn}</code>
                  <div class="text-xs opacity-80">
                    {t("ldap.credentials.used", { used: since(credential.usedAt, t("ldap.credentials.never")) })}
                  </div>
                </div>
                <button type="button" class="btn btn-ghost btn-sm" onclick={() => revoke(credential)}>
                  {t("ldap.credentials.revoke")}
                </button>
              </li>
            {/each}
          </ul>
        {/if}
      </Section>

      <Section row title={t("ldap.binds.title")} help={t("ldap.binds.help")}>
        <Switch label={t("ldap.binds.password_only")} checked={data.tenant.ldapPasswordOnly} onchange={passwordOnly} />
      </Section>
    </div>
  {/if}
</Page>
