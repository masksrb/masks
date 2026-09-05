<script>
import Identified from "../shared/Identified.svelte";
import PasskeyButton from "../shared/PasskeyButton.svelte";

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
  <h1 class="prompt-title">Enter your password</h1>
</div>

<Identified {login} />

<form {onsubmit} class="flow">
  <label class="field">
    <span class="field-label">Password</span>
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
    {login.loading ? "Checking" : "Continue"}
  </button>
</form>

<PasskeyButton {login} label="Use a passkey" />

<button
  type="button"
  class="action action-plain"
  disabled={login.loading}
  onclick={() => login.submit("forgot-password", {})}
>
  Forgot it?
</button>
