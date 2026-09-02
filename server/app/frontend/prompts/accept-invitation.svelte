<script>
import PromptHeader from "../shared/PromptHeader.svelte";

let { login } = $props();

let password = $state("");

const invitation = $derived(login.auth.invitation ?? {});
const minimum = $derived(invitation.minimum ?? 8);

const heading = $derived(
  login.auth.tenant?.name ? `Join ${login.auth.tenant.name}` : "Join",
);

const valid = $derived(password.length >= minimum);

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("accept-invitation", { password });
  }
}
</script>

<PromptHeader {heading} {login} />

<p class="text-sm opacity-75">
  {#if invitation.invitedBy}{invitation.invitedBy} invited you.{/if}
  Choose a password and the account is yours.
</p>

<form {onsubmit} class="flex flex-col gap-4">
  <label class="flex flex-col gap-1.5">
    <span class="text-sm font-medium">Username</span>
    <input
      type="text"
      class="input input-bordered w-full"
      autocomplete="username"
      value={invitation.nickname ?? ""}
      readonly
    />
  </label>

  {#if invitation.email}
    <label class="flex flex-col gap-1.5">
      <span class="text-sm font-medium">Email</span>
      <input
        type="email"
        class="input input-bordered w-full"
        value={invitation.email}
        readonly
      />
    </label>
  {/if}

  <label class="flex flex-col gap-1.5">
    <span class="text-sm font-medium">Password</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="password"
      name="password"
      class="input input-bordered w-full"
      autocomplete="new-password"
      autofocus
      bind:value={password}
    />
    <span class="text-xs opacity-75">At least {minimum} characters.</span>
  </label>

  <button
    type="submit"
    class="btn btn-primary w-full"
    disabled={!valid || login.loading}
  >
    {#if login.loading}<span class="loading loading-spinner loading-sm"></span>{/if}
    {login.loading ? "Accepting..." : "Accept the invitation"}
  </button>
</form>
