<script>
import Identified from "../shared/Identified.svelte";

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

<div class="prompt-head">
  <h1 class="prompt-title">Use a backup code</h1>
</div>

<Identified {login} />

<form {onsubmit} class="flow">
  <label class="field">
    <span class="field-label">Backup code</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="text"
      name="backup_code"
      class="control control-mono"
      autocomplete="one-time-code"
      spellcheck="false"
      autocapitalize="off"
      autofocus
      bind:value={code}
    />
    <span class="field-hint">Each one works once.</span>
  </label>

  <button type="submit" class="action" disabled={!valid || login.loading}>
    {#if login.loading}<span class="spinner"></span>{/if}
    {login.loading ? "Checking" : "Continue"}
  </button>
</form>

<button
  type="button"
  class="action action-plain"
  onclick={() => login.submit("use-authenticator", {})}
>
  Use your authenticator
</button>
