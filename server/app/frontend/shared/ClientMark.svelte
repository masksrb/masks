<script>
import { initial } from "../lib/initial.js";

let { client } = $props();
</script>

{#if client?.logo}
  <img src={client.logo} alt="" class="auth-mark auth-mark-client auth-mark-logo" referrerpolicy="no-referrer" />
{:else}
  <span class="auth-mark auth-mark-client" aria-hidden="true">{initial(client?.name)}</span>
{/if}
