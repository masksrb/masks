<script>
import Action from "./Action.svelte";

let { login } = $props();

let sent = $state(false);

async function resend() {
  await login.submit("confirm:resend", {});
  sent = true;
}
</script>

<Action
  {login}
  plain
  ready={login.auth.confirmation?.resendable !== false}
  label={sent ? login.t("sent_again") : login.t("send_again")}
  onclick={resend}
/>
