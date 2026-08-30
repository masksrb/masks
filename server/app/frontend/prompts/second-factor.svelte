<script>
import Identified from "../shared/Identified.svelte";
import PromptHeader from "../shared/PromptHeader.svelte";

let { login } = $props();

let code = $state("");

const valid = $derived(code.replace(/\s/g, "").length === 6);

function submit() {
  if (!valid || login.loading) return;

  const entered = code;
  code = "";

  login.submit("otp", { code: entered });
}

function onsubmit(event) {
  event.preventDefault();
  submit();
}

$effect(() => {
  if (valid) submit();
});
</script>

<PromptHeader heading="Enter your code" {login} />

<Identified {login} />

<form {onsubmit} class="flex flex-col gap-4">
  <label class="flex flex-col gap-1.5">
    <span class="text-sm font-medium">Six-digit code</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="text"
      name="code"
      class="input input-bordered w-full text-lg tabular-nums tracking-[0.4em]"
      inputmode="numeric"
      pattern="[0-9]*"
      autocomplete="one-time-code"
      maxlength="6"
      spellcheck="false"
      autofocus
      bind:value={code}
    />
    <span class="text-xs opacity-75">From your authenticator app.</span>
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
