<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";
import { ranked } from "../lib/scopes.js";

let { login } = $props();

const scopes = $derived(ranked(login.consent?.scopes ?? []));
const audience = $derived(login.consent?.audience ?? []);
const client = $derived(login.client?.name ?? "");
const tenant = $derived(login.auth.tenant?.name ?? "");

const initial = (name) => (name ? name.slice(0, 1).toUpperCase() : "");
</script>

<div class="auth-pair">
  <span class="auth-mark auth-mark-client" aria-hidden="true">{initial(client)}</span>
  <span class="auth-wire"></span>
  <span class="auth-mark" aria-hidden="true">{initial(tenant)}</span>
</div>

<Head {login} title={login.t("title", { client })} />

<div class="slab">
  <div class="ledger-row">
    <span class="ledger-label">{login.t("access")}</span>

    {#if !scopes.hot.length && !scopes.rest.length}
      <p class="empty">{login.t("no_access")}</p>
    {/if}

    <ul class="grant-scopes">
      {#each scopes.hot as [scope, description] (scope)}
        <li class="grant-scope grant-scope-hot">
          <span>{description}</span>
          <span class="chip-key">{scope}</span>
        </li>
      {/each}

      {#if scopes.hot.length && scopes.rest.length}
        <li class="grant-scope-split"></li>
      {/if}

      {#each scopes.rest as [scope, description] (scope)}
        <li class="grant-scope">
          <span>{description}</span>
          <span class="chip-key">{scope}</span>
        </li>
      {/each}
    </ul>
  </div>

  {#if audience.length}
    <div class="ledger-row">
      <span class="ledger-label">{login.t("audience")}</span>
      {#each audience as resource (resource)}
        <span class="ledger-value aside-mono">{resource}</span>
      {/each}
    </div>
  {/if}
</div>

<div class="action-row">
  <Action
    {login}
    grow
    busy={login.loading}
    label={login.t("allow")}
    working={login.t("working")}
    onclick={() => login.submit("consent", { approve: "yes" })}
  />

  <Action
    {login}
    quiet
    fit
    label={login.t("deny")}
    onclick={() => login.submit("decline", {})}
  />
</div>

<p class="aside">
  {login.actor?.nickname} · <a class="textlink" href="/logout">{login.t("sign_out")}</a>
</p>
