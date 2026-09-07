<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";
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

<Head {login} title={login.t("title")} />

<Identified {login} />

<form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
  <label class="field">
    <span class="field-label">{login.t("code")}</span>
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
    <span class="field-hint">{login.t("hint")}</span>
  </label>

  <Action
    {login}
    type="submit"
    ready={valid}
    busy={login.loading}
    label={login.t("continue")}
    working={login.t("checking")}
  />
</form>

<Action
  {login}
  plain
  label={login.t("use_authenticator")}
  onclick={() => login.submit("use-authenticator", {})}
/>
