<script>
let { heading, login } = $props();

const client = $derived(login.auth.client);
</script>

<div class="flex flex-col gap-1">
  <h1 class="text-2xl font-bold">{heading}</h1>

  {#if client?.name}
    <p class="text-sm opacity-75">
      to continue to <strong class="font-semibold">{client.name}</strong>
    </p>
  {/if}
</div>
