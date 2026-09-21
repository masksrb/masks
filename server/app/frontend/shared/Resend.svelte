<script>
import Action from "./Action.svelte";

let { login, event = "confirm:resend", ready = null } = $props();

let sent = $state(false);

async function resend() {
  await login.submit(event, {});
  sent = true;
}
</script>

<Action
  {login}
  plain
  ready={ready ?? login.auth.confirmation?.resendable !== false}
  label={sent ? login.t("sent_again") : login.t("send_again")}
  onclick={resend}
/>
