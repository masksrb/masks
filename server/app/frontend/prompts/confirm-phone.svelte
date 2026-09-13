<script>
import Action from "../shared/Action.svelte";
import ConfirmHead from "../shared/ConfirmHead.svelte";
import Resend from "../shared/Resend.svelte";

let { login } = $props();

const confirmation = $derived(login.auth.confirmation ?? {});

let code = $state("");

const valid = $derived(code.replace(/\D/g, "").length === 6);

function submit() {
  if (!valid || login.loading) return;

  const entered = code;
  code = "";

  login.submit("confirm:phone", { code: entered });
}

function onsubmit(event) {
  event.preventDefault();
  submit();
}

$effect(() => {
  if (valid) submit();
});
</script>

<ConfirmHead {login} title={login.t("title")} lede={login.t("lede", { phone: confirmation.phone })} />

{#if !confirmation.texts}
  <p class="note note-warn" role="alert">{login.t("no_texts")}</p>
{:else}
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

  <Resend {login} />
{/if}

<Action {login} plain label={login.t("change_phone")} onclick={() => login.submit("confirm:change-phone", {})} />
