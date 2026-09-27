<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";
import Identified from "../shared/Identified.svelte";
import Otherwise from "../shared/Otherwise.svelte";

let { login } = $props();

let password = $state("");

const valid = $derived(password.length > 0);
const offersPassword = $derived(login.auth.passwordOffered !== false);
const emailing = $derived(Boolean(login.auth.emailCode?.offered));

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("password", { password }).then(() => {
      password = "";
    });
  }
}
</script>

<Head {login} title={offersPassword ? login.t("title") : login.t("title_code")} />

<Identified {login} />

{#if offersPassword}
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
{/if}

{#if emailing}
  <Action
    {login}
    quiet={offersPassword}
    label={offersPassword ? login.t("email_me") : login.t("email_only")}
    onclick={() => login.submit("email-code:send", {})}
  />
{/if}

<Otherwise {login} />
