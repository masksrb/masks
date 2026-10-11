<script>
import { initial } from "../lib/initial.js";

let { tenant } = $props();
</script>

{#if tenant?.logo}
  <img src={tenant.logo} alt="" class="auth-mark auth-mark-logo" />
{:else}
  <span class="auth-mark" aria-hidden="true">{initial(tenant?.name ?? "")}</span>
{/if}
