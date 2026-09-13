<script>
import Action from "./Action.svelte";
import { assert, available, enrol, refused } from "../lib/passkey.js";

let { login, enrolling = false, label = null } = $props();

let busy = $state(false);
let unusable = $state(null);

const offered = $derived((enrolling || Boolean(login.auth.passkey?.offered)) && available());

async function start() {
  busy = true;
  unusable = null;

  try {
    const offer = await login.submit(enrolling ? "enrol:passkey-challenge" : "passkey:challenge", {});
    const options = enrolling ? offer.enrolment?.passkeys?.options : offer.passkey?.options;

    if (!options) {
      unusable = login.t("passkey_unoffered");
      return;
    }

    const credential = enrolling ? await enrol(options) : await assert(options);

    await login.submit(enrolling ? "enrol:passkey" : "passkey:verify", { passkey: credential });
  } catch (error) {
    if (!refused(error)) {
      unusable = login.t("passkey_unusable");
    }
  } finally {
    busy = false;
  }
}
</script>

{#if offered}
  <div class="flow-tight">
    <Action
      {login}
      quiet
      {busy}
      label={label ?? login.t("use_passkey")}
      working={login.t("waiting_for_passkey")}
      onclick={start}
    />

    {#if busy}
      <p class="aside">{login.t("passkey_hint")}</p>
    {/if}

    {#if unusable}
      <p class="aside aside-bad" role="alert">{unusable}</p>
    {/if}
  </div>
{/if}
