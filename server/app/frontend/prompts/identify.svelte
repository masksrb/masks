<script>
import PromptHeader from "../shared/PromptHeader.svelte";

let { login } = $props();

let identifier = $state("");

const heading = $derived(
  login.auth.tenant?.name ? `Log in to ${login.auth.tenant.name}` : "Log in",
);

const valid = $derived(identifier.trim().length > 0);

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("identify", { identifier });
  }
}
</script>

<PromptHeader {heading} {login} />

<form {onsubmit} class="flex flex-col gap-4">
  <label class="flex flex-col gap-1.5">
    <span class="text-sm font-medium">Username or email</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="text"
      name="identifier"
      class="input input-bordered w-full"
      autocomplete="username"
      autocapitalize="none"
      autocorrect="off"
      spellcheck="false"
      autofocus
      bind:value={identifier}
    />
  </label>

  <button
    type="submit"
    class="btn btn-primary w-full"
    disabled={!valid || login.loading}
  >
    {#if login.loading}<span class="loading loading-spinner loading-sm"></span>{/if}
    {login.loading ? "Checking..." : "Continue"}
  </button>
</form>
