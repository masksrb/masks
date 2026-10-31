<script>
import Action from "../shared/Action.svelte";
import ClientMark from "../shared/ClientMark.svelte";
import Head from "../shared/Head.svelte";
import Actor from "../shared/Actor.svelte";
import { ranked } from "../lib/scopes.js";

let { login } = $props();

const scopes = $derived(ranked(login.consent?.scopes ?? []));
const all = $derived([...scopes.hot, ...scopes.rest]);
const audience = $derived(login.consent?.audience ?? []);
const details = $derived(login.consent?.details ?? []);
const client = $derived(login.client?.name ?? "");
const links = $derived(
  [
    ["site", login.t("site", { client })],
    ["terms", login.t("terms")],
    ["privacy", login.t("privacy")],
  ].filter(([key]) => login.client?.[key]),
);
</script>

<div class="auth-solo">
  <ClientMark client={login.client} />
</div>

<Head {login} title={login.t("title", { client })} />

{#if login.auth.actor?.card}
  <Actor actor={login.auth.actor.card} signOut={login.t("sign_out")} />
{/if}

<div class="slab">
  <div class="ledger-row">
    <span class="ledger-label">{login.t("access")}</span>

    {#if all.length}
      <ul class="plain-list">
        {#each all as [scope, description] (scope)}
          <li>{description}</li>
        {/each}
      </ul>
    {:else}
      <p class="empty">{login.t("no_access")}</p>
    {/if}
  </div>

  {#if audience.length}
    <div class="ledger-row">
      <span class="aside">{login.t("audience", { resources: audience.join(", ") })}</span>
    </div>
  {/if}

  {#if details.length}
    <div class="ledger-row">
      <span class="ledger-label">{login.t("details")}</span>
      <ul class="plain-list">
        {#each details as detail, index (index)}
          <li>
            {detail.label}
            {#if detail.fields.length}
              <dl class="grant-fields">
                {#each detail.fields as [name, value] (name)}
                  <dt>{name}</dt>
                  <dd class="aside-mono">{value}</dd>
                {/each}
              </dl>
            {/if}
          </li>
        {/each}
      </ul>
    </div>
  {/if}
</div>

<details class="disclosure handshake-more">
  <summary class="textlink">{login.t("more")}</summary>

  <div class="slab">
    <div class="ledger-row">
      <span class="ledger-label">{login.t("scopes")}</span>
      <ul class="grant-scopes">
        {#each all as [scope, description] (scope)}
          <li class="grant-scope">
            <span>{description}</span>
            <span class="chip-key">{scope}</span>
          </li>
        {/each}
      </ul>
    </div>

    {#if login.client?.returnsTo}
      <div class="ledger-row">
        <span class="ledger-label">{login.t("returns_to")}</span>
        <span class="ledger-value aside-mono">{login.client.returnsTo}</span>
      </div>
    {/if}

    {#if links.length}
      <p class="aside client-links">
        {#each links as [key, label] (key)}
          <a class="textlink" href={login.client[key]} rel="noopener noreferrer" target="_blank">{label}</a>
        {/each}
      </p>
    {/if}
  </div>
</details>

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
