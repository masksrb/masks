<script>
import Action from "../shared/Action.svelte";
import SignupHead from "../shared/SignupHead.svelte";

let { login } = $props();

const signup = $derived(login.auth.signup ?? {});
const firstRun = $derived(Boolean(signup.firstRun));
const minimum = $derived(signup.minimum ?? 8);
const docs = $derived(login.auth.docs);

const rows = $derived(
  [
    ["name", signup.name],
    ["nickname", signup.nickname],
    ["email", signup.email],
    ["phone", signup.phone],
  ].filter(([, value]) => value),
);

let password = $state("");
let confirmation = $state("");

const long = $derived(password.length >= minimum);
const matched = $derived(long && confirmation === password);

function onsubmit(event) {
  event.preventDefault();

  if (matched && !login.loading) {
    login.submit("signup", { password, password_confirmation: confirmation });
  }
}
</script>

<div class="setup flow" class:setup-ready={matched}>
  <SignupHead {login} {firstRun} steps={signup.steps} at={2} mark={signup.nickname || signup.email || ""} />

  <form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
    <div class="slab">
      {#each rows as [field, value] (field)}
        <div class="ledger-row ledger-row-aside">
          <span class="ledger-label">{login.t(field)}</span>
          <span class="ledger-value">{value}</span>
          <button
            type="button"
            class="textlink ledger-aside"
            disabled={login.loading}
            onclick={() => login.submit("signup-edit")}>{login.t("edit")}</button>
        </div>
      {/each}

      <label class="ledger-row ledger-step" class:ledger-step-done={long}>
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

      <label class="ledger-row ledger-step" class:ledger-step-done={matched}>
        <span class="ledger-label">{login.t("confirm")}</span>
        <input
          type="password"
          name="password_confirmation"
          class="control"
          autocomplete="new-password"
          bind:value={confirmation}
        />
      </label>
    </div>

    <Action
      {login}
      type="submit"
      ready={matched}
      busy={login.loading}
      label={firstRun ? login.t("submit_first_run") : login.t("submit")}
      working={login.t("working")}
    />
  </form>

  {#if firstRun}
    <p class="aside">
      {login.t("once")}
      {#if docs}
        <a class="textlink" href={docs} rel="noopener" target="_blank">{login.t("docs")}</a>
      {/if}
    </p>
  {/if}
</div>
