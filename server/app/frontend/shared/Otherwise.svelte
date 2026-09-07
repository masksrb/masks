<script>
import PasskeyButton from "./PasskeyButton.svelte";
import ProviderButtons from "./ProviderButtons.svelte";
import { available } from "../lib/passkey.js";

let { login } = $props();

const passkey = $derived(Boolean(login.auth.passkey?.offered) && available());
const providers = $derived((login.auth.providers ?? []).length > 0);
</script>

{#if passkey || providers}
  <div class="otherwise">
    <span class="providers-rule">{login.t("or")}</span>

    <PasskeyButton {login} />

    <ProviderButtons {login} />
  </div>
{/if}
