<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";

let { login } = $props();

let password = $state("");

const reset = $derived(login.auth.reset ?? {});
const minimum = $derived(reset.minimum ?? 8);

const valid = $derived(password.length >= minimum);

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("reset-password", { password });
  }
}
</script>

<Head {login} title={login.t("title")} />

<form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
  <label class="field">
    <span class="field-label">{login.t("username")}</span>
    <input
      type="text"
      class="control"
      autocomplete="username"
      value={reset.nickname ?? ""}
      readonly
    />
  </label>

  <label class="field">
    <span class="field-label">{login.t("password")}</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="password"
      name="password"
      class="control"
      autocomplete="new-password"
      autofocus
      bind:value={password}
    />
    <span class="field-hint">{login.t("hint", { minimum })}</span>
  </label>

  <Action
    {login}
    type="submit"
    ready={valid}
    busy={login.loading}
    label={login.t("continue")}
    working={login.t("working")}
  />
</form>
