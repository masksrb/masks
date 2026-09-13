<script>
import Action from "../shared/Action.svelte";
import CodeForm from "../shared/CodeForm.svelte";
import ConfirmHead from "../shared/ConfirmHead.svelte";
import Resend from "../shared/Resend.svelte";

let { login } = $props();

const confirmation = $derived(login.auth.confirmation ?? {});
</script>

<ConfirmHead {login} title={login.t("title")} lede={login.t("lede", { phone: confirmation.phone })} />

{#if confirmation.texts}
  <CodeForm {login} event="confirm:phone" />

  <Resend {login} />
{:else}
  <p class="note note-warn" role="alert">{login.t("no_texts")}</p>
{/if}

<Action {login} plain label={login.t("change_phone")} onclick={() => login.submit("confirm:change-phone", {})} />
