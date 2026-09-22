<script>
import { initial } from "../lib/initial.js";
import Action from "../shared/Action.svelte";
import ClientMark from "../shared/ClientMark.svelte";
import Head from "../shared/Head.svelte";
import Person from "../shared/Person.svelte";
import { ranked } from "../lib/scopes.js";

let { login } = $props();

const scopes = $derived(ranked(login.consent?.scopes ?? []));
const audience = $derived(login.consent?.audience ?? []);
const client = $derived(login.client?.name ?? "");
const tenant = $derived(login.auth.tenant?.name ?? "");
const links = $derived(
  [
    ["site", login.t("site", { client })],
    ["terms", login.t("terms")],
    ["privacy", login.t("privacy")],
  ].filter(([key]) => login.client?.[key]),
);

</script>

<div class="auth-pair">
  <ClientMark client={login.client} />
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

  {#if login.client?.returnsTo}
    <div class="ledger-row">
      <span class="ledger-label">{login.t("returns_to")}</span>
      <span class="ledger-value aside-mono">{login.client.returnsTo}</span>
    </div>
  {/if}
</div>

{#if links.length}
  <p class="aside client-links">
    {#each links as [key, label] (key)}
      <a class="textlink" href={login.client[key]} rel="noopener noreferrer" target="_blank">{label}</a>
    {/each}
  </p>
{/if}

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

{#if login.auth.person}
  <Person person={login.auth.person} signOut={login.t("sign_out")} />
{/if}
