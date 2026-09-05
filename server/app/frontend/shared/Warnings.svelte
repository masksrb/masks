<script>
let { login } = $props();

const messages = $derived(login.auth.messages ?? []);
</script>

{#each messages as message (message.key)}
  <div class={message.tone} role="alert">{message.text}</div>
{/each}

{#if login.failed}
  <div class="note note-warn" role="alert">
    Could not reach the server. Check your connection.
  </div>
{/if}
