<script>
import { assert, available, refused } from "../lib/passkey.js";

let { login, label = "Sign in with a passkey" } = $props();

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
  <button
    type="button"
    class="btn btn-outline w-full"
    disabled={busy || login.loading}
    onclick={start}
  >
    {#if busy}<span class="loading loading-spinner loading-sm"></span>{/if}
    {busy ? "Waiting for your passkey..." : label}
  </button>

  {#if unusable}
    <p class="text-xs text-error">{unusable}</p>
  {/if}
{/if}
