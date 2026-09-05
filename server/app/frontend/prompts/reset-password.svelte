<script>
import PromptHeader from "../shared/PromptHeader.svelte";

let { login } = $props();

let password = $state("");

const reset = $derived(login.auth.reset ?? {});
const minimum = $derived(reset.minimum ?? 8);

const valid = $derived(password.length >= minimum);

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("reset-password", { password });
  }
}
</script>

<PromptHeader heading="Set a new password" {login} />

<p class="prompt-lede">
  Setting a password here signs {reset.nickname} out everywhere else.
</p>

<form {onsubmit} class="flow">
  <label class="field">
    <span class="field-label">Username</span>
    <input
      type="text"
      class="control"
      autocomplete="username"
      value={reset.nickname ?? ""}
      readonly
    />
  </label>

  <label class="field">
    <span class="field-label">New password</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="password"
      name="password"
      class="control"
      autocomplete="new-password"
      autofocus
      bind:value={password}
    />
    <span class="field-hint">At least {minimum} characters.</span>
  </label>

  <button type="submit" class="action" disabled={!valid || login.loading}>
    {#if login.loading}<span class="spinner"></span>{/if}
    {login.loading ? "Setting" : "Set the password"}
  </button>
</form>
