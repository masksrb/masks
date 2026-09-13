<script>
import Action from "../shared/Action.svelte";
import Otherwise from "../shared/Otherwise.svelte";
import ProviderButtons from "../shared/ProviderButtons.svelte";
import PromptHeader from "../shared/PromptHeader.svelte";

let { login } = $props();

let identifier = $state("");

const valid = $derived(identifier.trim().length > 0);

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
        autocomplete="username"
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
