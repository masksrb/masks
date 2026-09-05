<script>
let { heading, login } = $props();

const client = $derived(login.auth.client);
</script>

<div class="prompt-head">
  <h1 class="prompt-title">{heading}</h1>

  {#if client?.name}
    <p class="prompt-lede">to continue to <strong>{client.name}</strong></p>
  {/if}
</div>
