<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";
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

<Head {login} title={login.t("title")} />

<Identified {login} />

<form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
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

  <Action
    {login}
    type="submit"
    ready={valid}
    busy={login.loading}
    label={login.t("continue")}
    working={login.t("checking")}
  />
</form>

{#if login.backupCodes}
  <Action
    {login}
    plain
    label={login.t("use_backup_code")}
    onclick={() => login.submit("use-backup-code", {})}
  />
{/if}
