<script>
import Action from "../shared/Action.svelte";
import Hint from "../shared/Hint.svelte";
import SignupHead from "../shared/SignupHead.svelte";
import { available, enrol, refused } from "../lib/passkey.js";

let { login } = $props();

const signup = $derived(login.auth.signup ?? {});
const credentials = $derived(signup.credentials ?? { password: true, passkey: false });
const firstRun = $derived(Boolean(login.auth.journey?.firstRun));
const minimum = $derived(signup.minimum ?? 8);
const docs = $derived(login.auth.docs);
const passkeyable = $derived(Boolean(credentials.passkey) && available());
const submitLabel = $derived(firstRun ? login.t("submit_first_run") : login.t("submit_signup"));

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
let creating = $state(false);
let unusable = $state(null);

const long = $derived(password.length >= minimum);
const matched = $derived(long && confirmation === password);

function onsubmit(event) {
  event.preventDefault();

  if (matched && !login.loading) {
    login.submit("signup", { password, password_confirmation: confirmation });
  }
}

async function createPasskey() {
  creating = true;
  unusable = null;

  try {
    const offer = await login.submit("signup:passkey-challenge", {});
    const options = offer.signup?.passkeyOptions;

    if (!options) {
      unusable = login.t("passkey_unoffered");
      return;
    }

    await login.submit("signup:passkey", { passkey: await enrol(options) });
  } catch (error) {
    if (!refused(error)) {
      unusable = login.t("passkey_unusable");
    }
  } finally {
    creating = false;
  }
}
</script>

<div class="setup flow" class:setup-ready={matched}>
  <SignupHead {login} at={2} mark={signup.nickname || signup.email || ""} />

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

      {#if credentials.password}
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
          <Hint {login} field="password" hint={login.t("password_hint", { minimum })} />
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
          <Hint {login} field="password_confirmation" />
        </label>
      {/if}
    </div>

    {#if credentials.password}
      <Action
        {login}
        type="submit"
        ready={matched}
        busy={login.loading && !creating}
        label={submitLabel}
        working={login.t("working")}
      />
    {/if}
  </form>

  {#if passkeyable}
    <div class="flow-tight">
      {#if credentials.password}
        <span class="providers-rule">{login.t("or")}</span>
      {:else}
        <p class="aside">{login.t("passkey_lede")}</p>
      {/if}

      <Action
        {login}
        quiet={credentials.password}
        busy={creating}
        label={credentials.password ? login.t("with_passkey") : login.t("create_passkey")}
        working={login.t("waiting_for_passkey")}
        onclick={createPasskey}
      />

      {#if creating}
        <p class="aside">{login.t("passkey_hint")}</p>
      {/if}

      {#if unusable}
        <p class="aside aside-bad" role="alert">{unusable}</p>
      {/if}
    </div>
  {:else if !credentials.password}
    <p class="note note-warn" role="alert">{login.t("no_passkeys")}</p>
  {/if}

  {#if firstRun}
    <p class="aside">
      {login.t("once")}
      {#if docs}
        <a class="textlink" href={docs} rel="noopener" target="_blank">{login.t("docs")}</a>
      {/if}
    </p>
  {/if}
</div>
