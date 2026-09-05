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
    <span class="field-hint">
      One of the codes you saved when you set up your authenticator. Each one
      works once.
    </span>
  </label>

  <button type="submit" class="action" disabled={!valid || login.loading}>
    {#if login.loading}<span class="spinner"></span>{/if}
    {login.loading ? "Verifying" : "Verify"}
  </button>
</form>

<button
  type="button"
  class="action action-plain"
  onclick={() => login.submit("use-authenticator", {})}
>
  Use my authenticator instead
</button>
