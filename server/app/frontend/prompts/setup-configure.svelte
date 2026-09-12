<script>
import { untrack } from "svelte";
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";
import SetupSteps from "../shared/SetupSteps.svelte";

let { login } = $props();

const tenant = $derived(login.auth.tenant?.name ?? "");
const docs = $derived(login.auth.docs);
const manager = $derived(login.actor?.identifier ?? "");
const origin = typeof location === "undefined" ? "" : location.origin;

let called = $state(untrack(() => login.auth.setup?.called ?? ""));

const initial = (name) => (name ? name.trim().slice(0, 1).toUpperCase() : "");

const ready = $derived(called.trim().length > 0);

const step = $derived(
  `ledger-row ledger-step ledger-step-4${ready ? " ledger-step-done" : ""}`,
);

function onsubmit(event) {
  event.preventDefault();

  if (ready && !login.loading) {
    login.submit("setup-configure", { called });
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
      <label class={step}>
        <span class="ledger-label">{login.t("called")}</span>
        <!-- svelte-ignore a11y_autofocus -->
        <input
          type="text"
          name="called"
          class="control"
          autofocus
          bind:value={called}
        />
        <span class="field-hint">{login.t("called_hint")}</span>
      </label>

      <div class="ledger-row">
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
