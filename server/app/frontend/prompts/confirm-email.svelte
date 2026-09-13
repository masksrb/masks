<script>
import Action from "../shared/Action.svelte";
import ConfirmHead from "../shared/ConfirmHead.svelte";
import Resend from "../shared/Resend.svelte";

let { login } = $props();

const confirmation = $derived(login.auth.confirmation ?? {});
const linked = $derived(confirmation.mode === "link");

let code = $state("");

const valid = $derived(code.replace(/\D/g, "").length === 6);

function submit() {
  if (!valid || login.loading) return;

  const entered = code;
  code = "";

  login.submit("confirm:email", { code: entered });
}

function onsubmit(event) {
  event.preventDefault();
  submit();
}

$effect(() => {
  if (valid) submit();
});

$effect(() => {
  if (!linked) return;

  const timer = setInterval(() => {
    if (!login.loading) login.submit("confirm:check", {});
  }, 5000);

  return () => clearInterval(timer);
});
</script>

<ConfirmHead
  {login}
  title={linked ? login.t("title_link") : login.t("title")}
  lede={linked
    ? login.t("lede_link", { email: confirmation.email })
    : login.t("lede", { email: confirmation.email })}
/>

{#if !confirmation.mails}
  <p class="note note-warn" role="alert">{login.t("no_mailer")}</p>
{:else if linked}
  <p class="waiting aside">{login.t("waiting")}</p>
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
{/if}

{#if confirmation.mails}
  <Resend {login} />
{/if}
