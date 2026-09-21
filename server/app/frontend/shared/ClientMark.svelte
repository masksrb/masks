<script>
let { client } = $props();

const name = $derived(client?.name ?? "");
const initial = $derived(name.trim().slice(0, 1).toUpperCase());
</script>

{#if client?.logo}
  <img src={client.logo} alt="" class="auth-mark auth-mark-client auth-mark-logo" referrerpolicy="no-referrer" />
{:else}
  <span class="auth-mark auth-mark-client" aria-hidden="true">{initial}</span>
{/if}
