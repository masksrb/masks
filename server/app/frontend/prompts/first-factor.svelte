<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";
import Identified from "../shared/Identified.svelte";
import Otherwise from "../shared/Otherwise.svelte";

let { login } = $props();

let password = $state("");

const valid = $derived(password.length > 0);

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("password", { password }).then(() => {
      password = "";
    });
  }
}
</script>

<Head {login} title={login.t("title")} />

<Identified {login} />

<form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
  <div class="field">
    <div class="field-line">
      <label class="field-label" for="password">{login.t("password")}</label>

      <button
        type="button"
        class="textlink"
        disabled={login.loading}
        onclick={() => login.submit("forgot-password", {})}
      >
        {login.t("forgot")}
      </button>
    </div>

    <!-- svelte-ignore a11y_autofocus -->
    <input
      id="password"
      type="password"
      name="password"
      class="control"
      autocomplete="current-password"
      autofocus
      bind:value={password}
    />
  </div>

  <Action
    {login}
    type="submit"
    ready={valid}
    busy={login.loading}
    label={login.t("continue")}
    working={login.t("checking")}
  />
</form>

<Otherwise {login} />
