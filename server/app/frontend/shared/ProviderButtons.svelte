<script>
let { login } = $props();

const providers = $derived(login.auth.providers ?? []);
</script>

{#if providers.length}
  <div class="providers">
    <span class="providers-rule">{login.t("or")}</span>

    {#each providers as provider (provider.key)}
      <button
        type="button"
        class="action action-quiet"
        disabled={login.loading}
        onclick={() => login.submit("provider", { provider: provider.key })}
      >
        {login.t("continue_with", { provider: provider.name })}
      </button>
    {/each}
  </div>
{/if}
