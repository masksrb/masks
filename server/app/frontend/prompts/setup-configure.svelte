<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";
import SetupSteps from "../shared/SetupSteps.svelte";

let { login } = $props();

const setup = $derived(login.auth.setup ?? {});
const tenant = $derived(login.auth.tenant?.name ?? "");
const docs = $derived(login.auth.docs);
const manager = $derived(login.actor?.identifier ?? "");
const origin = typeof location === "undefined" ? "" : location.origin;

let called = $state(setup.called ?? "");
let mailFrom = $state(setup.mailFrom ?? "");
let smtpAddress = $state(setup.smtpAddress ?? "");
let smtpPort = $state(setup.smtpPort ?? 587);
let smtpUsername = $state(setup.smtpUsername ?? "");
let smtpPassword = $state("");
let smtpTls = $state(setup.smtpTls ?? false);

const initial = (name) => (name ? name.trim().slice(0, 1).toUpperCase() : "");

const ready = $derived(called.trim().length > 0);

function onsubmit(event) {
  event.preventDefault();

  if (ready && !login.loading) {
    login.submit("setup-configure", {
      called,
      mail_from: mailFrom,
      smtp_address: smtpAddress,
      smtp_port: String(smtpPort),
      smtp_username: smtpUsername,
      smtp_password: smtpPassword,
      smtp_tls: smtpTls ? "true" : "false",
    });
  }
}
</script>

<div class="setup flow" class:setup-ready={ready}>
  <div class="auth-pair">
    <span class="auth-mark auth-mark-client" aria-hidden="true"
      >{initial(manager)}</span>
    <span class="auth-wire"></span>
    <span class="auth-mark" aria-hidden="true">{initial(tenant)}</span>
  </div>

  <Head {login} title={login.t("title")} name={tenant} cap={login.t("cap")} />

  <SetupSteps {login} at={3} />

  <form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
    <div class="slab">
      <label class="ledger-row">
        <span class="ledger-label">{login.t("called")}</span>
        <input type="text" name="called" class="control" bind:value={called} />
        <span class="field-hint">{login.t("called_hint")}</span>
      </label>

      <label class="ledger-row">
        <span class="ledger-label">{login.t("mail_from")}</span>
        <input
          type="email"
          name="mail_from"
          class="control"
          autocomplete="off"
          bind:value={mailFrom}
        />
        <span class="field-hint">{login.t("mail_hint")}</span>
      </label>

      <label class="ledger-row">
        <span class="ledger-label">{login.t("smtp_address")}</span>
        <input
          type="text"
          name="smtp_address"
          class="control"
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          bind:value={smtpAddress}
        />
      </label>

      <label class="ledger-row">
        <span class="ledger-label">{login.t("smtp_port")}</span>
        <input
          type="number"
          name="smtp_port"
          class="control"
          bind:value={smtpPort}
        />
      </label>

      <label class="ledger-row">
        <span class="ledger-label">{login.t("smtp_username")}</span>
        <input
          type="text"
          name="smtp_username"
          class="control"
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          bind:value={smtpUsername}
        />
      </label>

      <label class="ledger-row">
        <span class="ledger-label">{login.t("smtp_password")}</span>
        <input
          type="password"
          name="smtp_password"
          class="control"
          autocomplete="off"
          bind:value={smtpPassword}
        />
      </label>

      <div class="ledger-row">
        <label class="check">
          <input type="checkbox" name="smtp_tls" bind:checked={smtpTls} />
          <span>{login.t("smtp_tls")}</span>
        </label>
      </div>

      <div class="ledger-row ledger-row-tight">
        <span class="ledger-label">{login.t("origin")}</span>
        <span class="ledger-value aside-mono">{origin}</span>
      </div>
    </div>

    <Action
      {login}
      type="submit"
      {ready}
      busy={login.loading}
      label={login.t("submit")}
      working={login.t("working")}
    />
  </form>

  <p class="aside">
    {login.t("once")}
    {#if docs}
      <a class="textlink" href={docs} rel="noopener" target="_blank"
        >{login.t("docs")}</a
      >
    {/if}
  </p>
</div>
