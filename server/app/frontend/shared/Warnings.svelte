<script>
let { login } = $props();

const messages = $derived(login.auth.messages ?? []);
</script>

{#each messages as message (message.key)}
  <div class={message.tone} role="alert">{message.text}</div>
{/each}

{#if login.failed}
  <div class="note note-warn recover" role="alert">
    <span>{login.t("unreachable")}</span>

    <button
      type="button"
      class="textlink"
      disabled={login.loading}
      onclick={() => login.retry()}
    >
      {login.loading ? login.t("checking") : login.t("try_again")}
    </button>
  </div>
{/if}
