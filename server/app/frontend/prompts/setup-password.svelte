<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";
import SetupSteps from "../shared/SetupSteps.svelte";

let { login } = $props();

const setup = $derived(login.auth.setup ?? {});
const minimum = $derived(setup.minimum ?? 8);
const nickname = $derived(setup.nickname ?? "");
const email = $derived(setup.email ?? "");
const tenant = $derived(login.auth.tenant?.name ?? "");
const docs = $derived(login.auth.docs);
const origin = typeof location === "undefined" ? "" : location.origin;

let password = $state("");
let confirmation = $state("");

const long = $derived(password.length >= minimum);
const matched = $derived(long && confirmation === password);
const valid = $derived(long && matched);

const step = (index, done) =>
  `ledger-row ledger-step ledger-step-${index}${done ? " ledger-step-done" : ""}`;

const initial = (name) => (name ? name.trim().slice(0, 1).toUpperCase() : "");

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("setup", {
      password,
      password_confirmation: confirmation,
    });
  }
}
</script>

<div class="setup flow" class:setup-ready={valid}>
  <div class="auth-pair">
    <span class="auth-mark auth-mark-client" aria-hidden="true"
      >{initial(nickname)}</span>
    <span class="auth-wire"></span>
    <span class="auth-mark" aria-hidden="true">{initial(tenant)}</span>
  </div>

  <Head {login} title={login.t("title")} name={tenant} cap={login.t("cap")} />

  <SetupSteps {login} at={2} />

  <form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
    <div class="slab">
      <div class="ledger-row ledger-row-aside">
        <span class="ledger-label">{login.t("nickname")}</span>
        <span class="ledger-value">{nickname}</span>
        <button
          type="button"
          class="textlink ledger-aside"
          disabled={login.loading}
          onclick={() => login.submit("setup-edit")}>{login.t("edit")}</button>
      </div>

      <div class="ledger-row ledger-row-aside">
        <span class="ledger-label">{login.t("email")}</span>
        <span class="ledger-value">{email}</span>
        <button
          type="button"
          class="textlink ledger-aside"
          disabled={login.loading}
          onclick={() => login.submit("setup-edit")}>{login.t("edit")}</button>
      </div>

      <label class={step(3, long)}>
        <span class="ledger-label">{login.t("password")}</span>
        <!-- svelte-ignore a11y_autofocus -->
        <input
          type="password"
          name="password"
          class="control"
          autocomplete="new-password"
          autofocus
          bind:value={password}
        />
        <span class="field-hint">{login.t("password_hint", { minimum })}</span>
      </label>

      <label class={step(4, matched)}>
        <span class="ledger-label">{login.t("confirm")}</span>
        <input
          type="password"
          name="password_confirmation"
          class="control"
          autocomplete="new-password"
          bind:value={confirmation}
        />
      </label>

      <div class="ledger-row">
        <span class="ledger-label">{login.t("origin")}</span>
        <span class="ledger-value aside-mono">{origin}</span>
      </div>
    </div>

    <Action
      {login}
      type="submit"
      ready={valid}
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
