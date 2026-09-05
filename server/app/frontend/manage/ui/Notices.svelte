<script>
  let { feedback } = $props();
</script>

{#if feedback.notice}
  <div class="alert alert-success alert-soft text-sm" role="status">{feedback.notice}</div>
{/if}

{#if feedback.failure}
  <div class="alert alert-error alert-soft text-sm" role="alert">{feedback.failure}</div>
{/if}
