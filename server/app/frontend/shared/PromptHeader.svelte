<script>
let { heading, login } = $props();

const client = $derived(login.auth.client);
const title = $derived(client?.name ? `${heading} to ${client.name}` : heading);
</script>

<div class="prompt-head">
  <h1 class="prompt-title">{title}</h1>
</div>
