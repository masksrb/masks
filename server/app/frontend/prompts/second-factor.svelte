<script>
import Identified from "../shared/Identified.svelte";
import PromptHeader from "../shared/PromptHeader.svelte";

let { login } = $props();

let code = $state("");
let remember = $state(false);

const valid = $derived(code.replace(/\s/g, "").length === 6);

function submit() {
  if (!valid || login.loading) return;

  const entered = code;
  code = "";

  login.submit("otp", { code: entered, remember });
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

<form {onsubmit} class="flow">
  <label class="field">
    <span class="field-label">Six-digit code</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="text"
      name="code"
      class="control control-code"
      inputmode="numeric"
      pattern="[0-9]*"
      autocomplete="one-time-code"
      maxlength="6"
      spellcheck="false"
      autofocus
      bind:value={code}
    />
    <span class="field-hint">From your authenticator app.</span>
  </label>

  {#if login.rememberable}
    <label class="check">
      <input type="checkbox" bind:checked={remember} />
      <span>Do not ask for a code on this device for 30 days</span>
    </label>
  {/if}

  <button type="submit" class="action" disabled={!valid || login.loading}>
    {#if login.loading}<span class="spinner"></span>{/if}
    {login.loading ? "Verifying" : "Verify"}
  </button>
</form>

{#if login.backupCodes}
  <button
    type="button"
    class="action action-plain"
    onclick={() => login.submit("use-backup-code", {})}
  >
    Use a backup code
  </button>
{/if}
