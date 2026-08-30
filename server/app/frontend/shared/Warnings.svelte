<script>
const MESSAGES = {
  "invalid-credentials": "That identifier and password do not match.",
  "invalid-code": "That code is not valid.",
  "missing-identifier": "Enter your username or email address.",
  "missing-first-factor": "That step expired. Start over and try again.",
  "too-many-attempts":
    "Too many sign-in attempts. Wait a few minutes and try again.",
  "too-many-attempts-for-account":
    "Too many sign-in attempts for that account.",
};

let { login } = $props();

const messages = $derived(
  (login.auth.warnings ?? []).map((key) => MESSAGES[key]).filter(Boolean),
);
</script>

{#each messages as message (message)}
  <div class="alert alert-error text-sm" role="alert">{message}</div>
{/each}

{#if login.failed}
  <div class="alert alert-warning text-sm" role="alert">
    Could not reach the server. Check your connection and try again.
  </div>
{/if}
