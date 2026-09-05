<script>
let { login } = $props();

const scopes = $derived(login.consent?.scopes ?? []);
const audience = $derived(login.consent?.audience ?? []);
</script>

<div class="prompt-head">
  <h1 class="prompt-title">{login.client?.name} wants access</h1>
  <p class="prompt-lede">
    Signed in as <strong>{login.actor?.nickname}</strong>.
  </p>
</div>

<div class="ledger">
  <div class="ledger-row">
    <span class="ledger-label">It is asking to</span>
    <ul class="grant-scopes">
      {#each scopes as [scope, description] (scope)}
        <li class="grant-scope">
          <span>{description ?? `Use the ${scope} scope`}</span>
          <span class="chip-key">{scope}</span>
        </li>
      {/each}
    </ul>
  </div>

  {#if audience.length}
    <div class="ledger-row">
      <span class="ledger-label">On your behalf at</span>
      {#each audience as resource (resource)}
        <span class="ledger-value aside-mono">{resource}</span>
      {/each}
    </div>
  {/if}
</div>

<div class="action-row">
  <button
    type="button"
    class="action action-grow"
    disabled={login.loading}
    onclick={() => login.submit("consent", { approve: "yes" })}
  >
    {#if login.loading}<span class="spinner"></span>{/if}
    {login.loading ? "Allowing" : "Allow"}
  </button>

  <button
    type="button"
    class="action action-quiet action-fit"
    disabled={login.loading}
    onclick={() => login.submit("decline", {})}
  >
    Deny
  </button>
</div>

<p class="aside">Not you? <a class="textlink" href="/logout">Sign out</a>.</p>
