<script>
let { login } = $props();

const scopes = $derived(login.consent?.scopes ?? []);
const audience = $derived(login.consent?.audience ?? []);
</script>

<div class="flex flex-col gap-1">
  <h1 class="text-2xl font-bold">{login.client?.name} wants access</h1>
  <p class="text-sm opacity-75">
    Signed in as <strong class="font-semibold">{login.actor?.nickname}</strong>.
  </p>
</div>

<h2 class="text-xs font-bold uppercase opacity-75">It is asking to</h2>
<ul class="flex flex-col gap-2">
  {#each scopes as [scope, description] (scope)}
    <li
      class="flex items-baseline justify-between gap-3 rounded-lg border border-base-content/15 bg-base-200 px-3 py-2"
    >
      <span class="text-sm">{description ?? `Use the ${scope} scope`}</span>
      <span class="font-mono text-xs opacity-75">{scope}</span>
    </li>
  {/each}
</ul>

{#if audience.length}
  <h2 class="text-xs font-bold uppercase opacity-75">On your behalf at</h2>
  {#each audience as resource (resource)}
    <p class="font-mono text-xs break-all opacity-75">{resource}</p>
  {/each}
{/if}

<div class="flex gap-2">
  <button
    type="button"
    class="btn btn-primary grow"
    disabled={login.loading}
    onclick={() => login.submit("consent", { approve: "yes" })}
  >
    {#if login.loading}<span class="loading loading-spinner loading-sm"></span>{/if}
    {login.loading ? "Allowing..." : "Allow"}
  </button>

  <button
    type="button"
    class="btn btn-ghost"
    disabled={login.loading}
    onclick={() => login.submit("decline", {})}
  >
    Deny
  </button>
</div>
