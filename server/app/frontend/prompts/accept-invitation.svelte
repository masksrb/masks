<script>
import PromptHeader from "../shared/PromptHeader.svelte";

let { login } = $props();

let password = $state("");

const invitation = $derived(login.auth.invitation ?? {});
const minimum = $derived(invitation.minimum ?? 8);

const valid = $derived(password.length >= minimum);

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("accept-invitation", { password });
  }
}
</script>

<PromptHeader heading="Accept your invitation" {login} />

<p class="prompt-lede">
  {#if invitation.invitedBy}{invitation.invitedBy} invited you.{/if}
  Choose a password and the account is yours.
</p>

<form {onsubmit} class="flow">
  <label class="field">
    <span class="field-label">Username</span>
    <input
      type="text"
      class="control"
      autocomplete="username"
      value={invitation.nickname ?? ""}
      readonly
    />
  </label>

  {#if invitation.email}
    <label class="field">
      <span class="field-label">Email</span>
      <input
        type="email"
        class="control"
        value={invitation.email}
        readonly
      />
    </label>
  {/if}

  <label class="field">
    <span class="field-label">Password</span>
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
    {login.loading ? "Accepting" : "Accept the invitation"}
  </button>
</form>
