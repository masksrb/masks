<script>
import Action from "./Action.svelte";

let { login } = $props();

const providers = $derived(login.auth.providers ?? []);
</script>

{#if providers.length}
  <div class="providers">
    {#each providers as provider (provider.key)}
      <Action
        {login}
        quiet
        label={login.t("continue_with", { provider: provider.name })}
        onclick={() => login.submit("provider", { provider: provider.key })}
      />
    {/each}
  </div>
{/if}
