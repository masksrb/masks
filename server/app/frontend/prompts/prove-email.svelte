<script>
import CodeForm from "../shared/CodeForm.svelte";
import Head from "../shared/Head.svelte";
import Identified from "../shared/Identified.svelte";
import Resend from "../shared/Resend.svelte";

let { login } = $props();

const inbox = $derived(login.auth.inbox ?? {});
</script>

<Head {login} title={login.t("title")} lede={inbox.mails ? login.t("lede", { email: inbox.email }) : null} />

<Identified {login} />

{#if inbox.mails}
  <CodeForm {login} event="inbox:verify" />
  <Resend {login} event="inbox:resend" ready={inbox.resendable !== false} />
{:else}
  <p class="note note-warn" role="alert">{login.t("no_mailer")}</p>
{/if}
