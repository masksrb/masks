<script>
import PromptHeader from "../shared/PromptHeader.svelte";

let { login } = $props();

let token = $state("");
let nickname = $state("");
let email = $state("");
let password = $state("");

const minimum = 8;

const heading = $derived(
  login.auth.tenant?.name ? `Set up ${login.auth.tenant.name}` : "Set up",
);

const needsToken = $derived(login.auth.setup?.token === true);

const valid = $derived(
  nickname.trim().length > 0 &&
    email.trim().length > 0 &&
    password.length >= minimum &&
    (!needsToken || token.length > 0),
);

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("setup", { token, nickname, email, password });
  }
}
</script>

<PromptHeader {heading} {login} />

<p class="text-sm opacity-75">
  Nobody has an account here yet. The first one you make owns this tenant.
</p>

<form {onsubmit} class="flex flex-col gap-4">
  {#if needsToken}
    <label class="flex flex-col gap-1.5">
      <span class="text-sm font-medium">Setup token</span>
      <input
        type="password"
        name="token"
        class="input input-bordered w-full"
        autocomplete="off"
        bind:value={token}
      />
      <span class="text-xs opacity-75">Whoever deployed this server set one.</span>
    </label>
  {/if}

  <label class="flex flex-col gap-1.5">
    <span class="text-sm font-medium">Username</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="text"
      name="nickname"
      class="input input-bordered w-full"
      autocomplete="username"
      autocapitalize="none"
      autocorrect="off"
      spellcheck="false"
      autofocus
      bind:value={nickname}
    />
  </label>

  <label class="flex flex-col gap-1.5">
    <span class="text-sm font-medium">Email</span>
    <input
      type="email"
      name="email"
      class="input input-bordered w-full"
      autocomplete="email"
      bind:value={email}
    />
    <span class="text-xs opacity-75">
      Applications you sign in to are given this address, and most refuse an account without one.
    </span>
  </label>

  <label class="flex flex-col gap-1.5">
    <span class="text-sm font-medium">Password</span>
    <input
      type="password"
      name="password"
      class="input input-bordered w-full"
      autocomplete="new-password"
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
    {login.loading ? "Creating..." : "Create the owner"}
  </button>
</form>
