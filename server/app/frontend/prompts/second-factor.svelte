<script>
import Identified from "../shared/Identified.svelte";

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

<div class="prompt-head">
  <h1 class="prompt-title">{login.t("title")}</h1>
</div>

<Identified {login} />

<form {onsubmit} class="flow">
  <label class="field">
    <span class="field-label">{login.t("code")}</span>
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
  </label>

  {#if login.rememberable}
    <label class="check">
      <input type="checkbox" bind:checked={remember} />
      <span>{login.t("trust", { duration: login.auth.trustFor })}</span>
    </label>
  {/if}

  <button type="submit" class="action" disabled={!valid || login.loading}>
    {#if login.loading}<span class="spinner"></span>{/if}
    {login.loading ? login.t("checking") : login.t("continue")}
  </button>
</form>

{#if login.backupCodes}
  <button
    type="button"
    class="action action-plain"
    onclick={() => login.submit("use-backup-code", {})}
  >
    {login.t("use_backup_code")}
  </button>
{/if}
