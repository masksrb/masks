<script>
import Identified from "../shared/Identified.svelte";
import PasskeyButton from "../shared/PasskeyButton.svelte";
import PromptHeader from "../shared/PromptHeader.svelte";

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

<PromptHeader heading="Enter your password" {login} />

<Identified {login} />

<form {onsubmit} class="flex flex-col gap-4">
  <label class="flex flex-col gap-1.5">
    <span class="text-sm font-medium">Password</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="password"
      name="password"
      class="input input-bordered w-full"
      autocomplete="current-password"
      autofocus
      bind:value={password}
    />
  </label>

  <button
    type="submit"
    class="btn btn-primary w-full"
    disabled={!valid || login.loading}
  >
    {#if login.loading}<span class="loading loading-spinner loading-sm"></span>{/if}
    {login.loading ? "Signing in..." : "Sign in"}
  </button>
</form>

<PasskeyButton {login} label="Use a passkey instead" />

<button
  type="button"
  class="link text-sm opacity-75 self-start"
  disabled={login.loading}
  onclick={() => login.submit("forgot-password", {})}
>
  Forgot your password?
</button>
