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
  "invitation-expired": "That invitation is no longer valid. Ask for another.",
  "reset-expired": "That reset link is no longer valid. Ask for another.",
  "no-mailer":
    "This server cannot send email, so it cannot reset a password. Ask an administrator.",
  "short-password": "That password is too short.",
};

const NOTICES = {
  "reset-sent":
    "If that account exists and can receive email, a reset link is on its way.",
};

let { login } = $props();

const shown = $derived(
  (login.auth.warnings ?? [])
    .map((key) =>
      NOTICES[key]
        ? { key, tone: "note", text: NOTICES[key] }
        : MESSAGES[key] && { key, tone: "note note-bad", text: MESSAGES[key] },
    )
    .filter(Boolean),
);
</script>

{#each shown as message (message.key)}
  <div class={message.tone} role="alert">{message.text}</div>
{/each}

{#if login.failed}
  <div class="note note-warn" role="alert">
    Could not reach the server. Check your connection and try again.
  </div>
{/if}
