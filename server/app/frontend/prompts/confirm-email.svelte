<script>
import CodeForm from "../shared/CodeForm.svelte";
import ConfirmHead from "../shared/ConfirmHead.svelte";
import Resend from "../shared/Resend.svelte";

let { login } = $props();

const confirmation = $derived(login.auth.confirmation ?? {});
const linked = $derived(confirmation.mode === "link");

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
  title={login.t("title")}
  lede={login.t(linked ? "lede_link" : "lede", { email: confirmation.email })}
/>

{#if !confirmation.mails}
  <p class="note note-warn" role="alert">{login.t("no_mailer")}</p>
{:else if linked}
  <p class="waiting aside">{login.t("waiting")}</p>
{:else}
  <CodeForm {login} event="confirm:email" />
{/if}

{#if confirmation.mails}
  <Resend {login} />
{/if}
