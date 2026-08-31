<script>
import Identified from "../shared/Identified.svelte";
import PromptHeader from "../shared/PromptHeader.svelte";

let { login } = $props();

let code = $state("");

const valid = $derived(code.trim().length >= 8);

function onsubmit(event) {
  event.preventDefault();

  if (!valid || login.loading) return;

  const entered = code;
  code = "";

  login.submit("backup", { backup_code: entered });
}
</script>

<PromptHeader heading="Use a backup code" {login} />

<Identified {login} />

<form {onsubmit} class="flex flex-col gap-4">
  <label class="flex flex-col gap-1.5">
    <span class="text-sm font-medium">Backup code</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="text"
      name="backup_code"
      class="input input-bordered w-full font-mono tracking-widest"
      autocomplete="one-time-code"
      spellcheck="false"
      autocapitalize="off"
      autofocus
      bind:value={code}
    />
    <span class="text-xs opacity-75">
      One of the codes you saved when you set up your authenticator. Each one
      works once.
    </span>
  </label>

  <button
    type="submit"
    class="btn btn-primary w-full"
    disabled={!valid || login.loading}
  >
    {#if login.loading}<span class="loading loading-spinner loading-sm"></span>{/if}
    {login.loading ? "Verifying..." : "Verify"}
  </button>
</form>

<button
  type="button"
  class="btn btn-ghost btn-sm w-full"
  onclick={() => login.submit("use-authenticator", {})}
>
  Use my authenticator instead
</button>
