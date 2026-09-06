<script>
import Identified from "../shared/Identified.svelte";
import PasskeyButton from "../shared/PasskeyButton.svelte";
import ProviderButtons from "../shared/ProviderButtons.svelte";

let { login } = $props();

let password = $state("");

const valid = $derived(password.length > 0);

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("password", { password }).then(() => {
      password = "";
    });
  }
}
</script>

<div class="prompt-head">
  <h1 class="prompt-title">{login.t("title")}</h1>
</div>

<Identified {login} />

<form {onsubmit} class="flow">
  <label class="field">
    <span class="field-label">{login.t("password")}</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="password"
      name="password"
      class="control"
      autocomplete="current-password"
      autofocus
      bind:value={password}
    />
  </label>

  <button type="submit" class="action" disabled={!valid || login.loading}>
    {#if login.loading}<span class="spinner"></span>{/if}
    {login.loading ? login.t("checking") : login.t("continue")}
  </button>
</form>

<PasskeyButton {login} />

<ProviderButtons {login} />

<button
  type="button"
  class="action action-plain"
  disabled={login.loading}
  onclick={() => login.submit("forgot-password", {})}
>
  {login.t("forgot")}
</button>
