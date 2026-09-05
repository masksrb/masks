<script>
import { assert, available, refused } from "../lib/passkey.js";

let { login, label = "Use a passkey" } = $props();

let busy = $state(false);
let unusable = $state(null);

const offered = $derived(Boolean(login.auth.passkey?.offered) && available());

async function start() {
  busy = true;
  unusable = null;

  try {
    const offer = await login.submit("passkey:challenge", {});
    const options = offer.passkey?.options;

    if (!options) {
      unusable = "This server did not offer a passkey challenge.";
      return;
    }

    const credential = await assert(options);

    await login.submit("passkey:verify", { passkey: credential });
  } catch (error) {
    if (!refused(error)) {
      unusable = "That passkey could not be used on this device.";
    }
  } finally {
    busy = false;
  }
}
</script>

{#if offered}
  <div class="flow-tight">
    <button
      type="button"
      class="action action-quiet"
      disabled={busy || login.loading}
      onclick={start}
    >
      {#if busy}<span class="spinner"></span>{/if}
      {busy ? "Waiting for your passkey" : label}
    </button>

    {#if unusable}
      <p class="aside aside-bad">{unusable}</p>
    {/if}
  </div>
{/if}
