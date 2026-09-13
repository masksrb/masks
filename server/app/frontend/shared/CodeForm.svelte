<script>
import Action from "./Action.svelte";

let { login, event } = $props();

let code = $state("");

const valid = $derived(code.replace(/\D/g, "").length === 6);

function submit() {
  if (!valid || login.loading) return;

  const entered = code;
  code = "";

  login.submit(event, { code: entered });
}

function onsubmit(submitted) {
  submitted.preventDefault();
  submit();
}

$effect(() => {
  if (valid) submit();
});
</script>

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

  <Action
    {login}
    type="submit"
    ready={valid}
    busy={login.loading}
    label={login.t("continue")}
    working={login.t("checking")}
  />
</form>
