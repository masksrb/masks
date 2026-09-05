<script>
import PromptHeader from "../shared/PromptHeader.svelte";

let { login } = $props();

let token = $state("");
let nickname = $state("");
let email = $state("");
let password = $state("");

const minimum = 8;

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

<PromptHeader heading="Create the owner" {login} />

<p class="prompt-lede">
  Nobody has an account here yet. The first one you make owns this tenant.
</p>

<form {onsubmit} class="flow">
  {#if needsToken}
    <label class="field">
      <span class="field-label">Setup token</span>
      <input
        type="password"
        name="token"
        class="control"
        autocomplete="off"
        bind:value={token}
      />
      <span class="field-hint">Whoever deployed this server set one.</span>
    </label>
  {/if}

  <label class="field">
    <span class="field-label">Username</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="text"
      name="nickname"
      class="control"
      autocomplete="username"
      autocapitalize="none"
      autocorrect="off"
      spellcheck="false"
      autofocus
      bind:value={nickname}
    />
  </label>

  <label class="field">
    <span class="field-label">Email</span>
    <input
      type="email"
      name="email"
      class="control"
      autocomplete="email"
      bind:value={email}
    />
    <span class="field-hint">
      Applications you sign in to are given this address, and most refuse an
      account without one.
    </span>
  </label>

  <label class="field">
    <span class="field-label">Password</span>
    <input
      type="password"
      name="password"
      class="control"
      autocomplete="new-password"
      bind:value={password}
    />
    <span class="field-hint">At least {minimum} characters.</span>
  </label>

  <button type="submit" class="action" disabled={!valid || login.loading}>
    {#if login.loading}<span class="spinner"></span>{/if}
    {login.loading ? "Creating" : "Create the owner"}
  </button>
</form>
