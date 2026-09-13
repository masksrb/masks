<script>
import { untrack } from "svelte";
import Action from "../shared/Action.svelte";
import SignupHead from "../shared/SignupHead.svelte";

let { login } = $props();

const docs = $derived(login.auth.docs);
const origin = typeof location === "undefined" ? "" : location.origin;

let called = $state(untrack(() => login.auth.configure?.called ?? ""));

const ready = $derived(called.trim().length > 0);

function onsubmit(event) {
  event.preventDefault();

  if (ready && !login.loading) {
    login.submit("setup-configure", { called });
  }
}
</script>

<div class="setup flow" class:setup-ready={ready}>
  <SignupHead {login} at={3} mark={login.actor?.identifier ?? ""} />

  <form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
    <div class="slab">
      <label class="ledger-row ledger-step" class:ledger-step-done={ready}>
        <span class="ledger-label">{login.t("called")}</span>
        <!-- svelte-ignore a11y_autofocus -->
        <input type="text" name="called" class="control" autofocus bind:value={called} />
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
      <a class="textlink" href={docs} rel="noopener" target="_blank">{login.t("docs")}</a>
    {/if}
  </p>
</div>
