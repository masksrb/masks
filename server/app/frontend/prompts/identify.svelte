<script>
import { onMount } from "svelte";
import { autofill, autofillable, settle } from "../lib/passkey.js";
import Action from "../shared/Action.svelte";
import Otherwise from "../shared/Otherwise.svelte";
import ProviderButtons from "../shared/ProviderButtons.svelte";
import PromptHeader from "../shared/PromptHeader.svelte";

let { login } = $props();

let identifier = $state("");

const valid = $derived(identifier.trim().length > 0);

onMount(() => {
  let live = true;

  (async () => {
    if (!login.auth.passkey?.offered || !(await autofillable()) || !live) return;

    const offer = await login.poll("passkey:challenge");
    const options = offer.passkey?.options;
    if (!options || !live) return;

    const passkey = await autofill(options);
    if (live) await login.submit("passkey:verify", { passkey });
  })().catch(() => {});

  return () => {
    live = false;
    settle();
  };
});

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("identify", { identifier });
  }
}
</script>

<PromptHeader {login} />

{#if login.auth.identifies !== false}
  <form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
    <label class="field">
      <span class="field-label">{login.t("identifier")}</span>
      <!-- svelte-ignore a11y_autofocus -->
      <input
        type="text"
        name="identifier"
        class="control"
        autocomplete="username webauthn"
        autocapitalize="none"
        autocorrect="off"
        spellcheck="false"
        autofocus
        bind:value={identifier}
      />
      {#if login.auth.signupOpen}
        <span class="field-hint">{login.t("signup_hint")}</span>
      {/if}
    </label>

    <Action
      {login}
      type="submit"
      ready={valid}
      busy={login.loading}
      label={login.t("continue")}
      working={login.t("checking")}
    />
  </form>

  <Otherwise {login} />
{:else}
  <ProviderButtons {login} />
{/if}
