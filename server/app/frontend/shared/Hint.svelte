<script>
let { login, field, hint = null } = $props();

const message = $derived((login.auth.messages ?? []).find((held) => held.field === field));
</script>

{#if message}
  <span class="field-hint field-hint-bad" role="alert">{message.text}</span>
{:else if hint}
  <span class="field-hint">{hint}</span>
{/if}
