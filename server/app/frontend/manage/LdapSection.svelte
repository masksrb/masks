<script>
  import { t } from "./lib/copy.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { since } from "./lib/format.js";
  import Section from "./ui/Section.svelte";
  import Notices from "./ui/Notices.svelte";
  import Switch from "./ui/Switch.svelte";

  let { api } = $props();

  const QUERY = `
    query Ldap {
      ldapBaseDn
      ldapPort
      ldapTls
      ldapLocalOnly
      ldapCredentials { id label bindDn usedAt createdAt issuedBy { identifier } }
      tenant { ldapEnabled ldapPasswordOnly }
    }
  `;

  const feedback = createFeedback();

  let data = $state(null);
  let label = $state("");
  let issued = $state(null);

  async function load() {
    try {
      data = await api.query(QUERY);
    } catch (thrown) {
      feedback.blame(thrown);
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

<Section row title={t("ldap.title")} help={`${t("ldap.lede")} ${t("ldap.serve.help")}`}>
  <Notices feedback={feedback.state} />

  {#if data}
    <Switch label={t("ldap.serve.on")} checked={data.tenant.ldapEnabled} onchange={serve} />

    {#if data.tenant.ldapEnabled}
      <dl class="ldap-facts">
        <dt class="field-label">{t("ldap.connect.address")}</dt>
        <dd><code class="font-mono text-xs">{t(data.ldapTls ? "ldap.connect.ldaps" : "ldap.connect.port", { port: data.ldapPort })}</code></dd>
        <dt class="field-label">{t("ldap.connect.base_dn")}</dt>
        <dd><code class="font-mono text-xs break-all">{data.ldapBaseDn}</code></dd>
      </dl>

      {#if data.ldapLocalOnly}
        <p class="hint">{t("ldap.connect.local_only")}</p>
      {/if}

      {#if data.ldapCredentials.length}
        <ul class="compact-list">
          {#each data.ldapCredentials as credential (credential.id)}
            <li>
              <div class="min-w-0">
                <div class="text-sm font-medium">{credential.label}</div>
                <code class="hint font-mono text-xs break-all">{credential.bindDn}</code>
                <div class="hint text-xs">
                  {t("ldap.credentials.used", { used: since(credential.usedAt, t("ldap.credentials.never")) })}
                </div>
              </div>
              <button type="button" class="btn btn-ghost btn-xs ml-auto" onclick={() => revoke(credential)}>
                {t("ldap.credentials.revoke")}
              </button>
            </li>
          {/each}
        </ul>
      {/if}

      <form
        class="join"
        onsubmit={(event) => {
          event.preventDefault();
          issue();
        }}
      >
        <input class="input input-sm join-item w-full max-w-48" aria-label={t("ldap.connect.label")} placeholder="jellyfin" bind:value={label} />
        <button type="submit" class="btn btn-sm join-item" disabled={!label.trim()}>{t("ldap.connect.issue")}</button>
      </form>
      <p class="hint">{t("ldap.connect.help")}</p>

      {#if issued}
        <div class="alert alert-warning alert-soft flex-col items-start gap-2" role="status">
          <span class="font-medium">{t("ldap.connect.shown_once")}</span>
          <span class="text-xs">{t("ldap.connect.bind_dn")}</span>
          <code class="font-mono text-xs break-all">{issued.ldapCredential.bindDn}</code>
          <span class="text-xs">{t("ldap.connect.secret")}</span>
          <code class="font-mono text-xs break-all">{issued.secret}</code>
        </div>
      {/if}

      <Switch label={t("ldap.binds.password_only")} checked={data.tenant.ldapPasswordOnly} onchange={passwordOnly} />
      <p class="hint">{t("ldap.binds.help")}</p>
    {/if}
  {/if}
</Section>
