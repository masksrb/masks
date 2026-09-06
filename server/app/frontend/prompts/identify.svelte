<script>
import PasskeyButton from "../shared/PasskeyButton.svelte";
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

<form {onsubmit} class="flow">
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
  </label>

  <button type="submit" class="action" disabled={!valid || login.loading}>
    {#if login.loading}<span class="spinner"></span>{/if}
    {login.loading ? login.t("checking") : login.t("continue")}
  </button>
</form>

<PasskeyButton {login} />
