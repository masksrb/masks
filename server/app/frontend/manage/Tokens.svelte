<script>
  import { joined, moment, since } from "./lib/format.js";
  import Link from "./ui/Link.svelte";

  let { api, feedback, rows, onchange, showActor = false } = $props();

  const REVOKE = `
    mutation Revoke($id: ID!, $family: Boolean) {
      revokeToken(id: $id, family: $family) { revoked }
    }
  `;

  const KIND = {
    access: "badge-ghost",
    refresh: "badge-info",
    code: "badge-warning",
  };

  async function revoke(token, family) {
    const held = showActor ? token.actor?.nickname : token.client?.name;
    const question = family
      ? `Revoke every token in this chain? Anything ${held} is holding stops working at once.`
      : `Revoke this ${token.kind} token? Whatever it was exchanged for goes with it.`;

    if (!confirm(question)) return;

    const data = await feedback.attempt(() =>
      api.query(REVOKE, { id: token.id, family }),
    );

    if (!data) return;

    const count = data.revokeToken.revoked;

    feedback.say(`${count} token${count === 1 ? "" : "s"} revoked.`);

    await onchange();
  }
</script>

{#if rows.length === 0}
  <p class="text-sm opacity-70">Nothing outstanding.</p>
{:else}
  <ul class="flex flex-col gap-1.5">
    {#each rows as token (token.id)}
      <li class="slat">
        <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
          <span class="flex flex-wrap items-baseline gap-2">
            <span class="badge badge-sm {KIND[token.kind] ?? 'badge-ghost'}">{token.kind}</span>

            {#if showActor && token.actor}
              <Link to={`/people/${token.actor.uuid}`} class="link link-hover text-sm font-medium">
                {token.actor.nickname}
              </Link>
            {:else if token.client}
              <Link
                to={`/clients/${token.client.clientId}`}
                class="link link-hover text-sm font-medium"
              >
                {token.client.name}
              </Link>
            {/if}

            {#if token.parentId}
              <span class="text-xs opacity-50">rotated</span>
            {/if}
          </span>

          <span class="flex items-baseline gap-3">
            <button type="button" class="link text-xs text-error" onclick={() => revoke(token, false)}>
              Revoke
            </button>
            {#if token.kind === "refresh"}
              <button
                type="button"
                class="link text-xs text-error"
                onclick={() => revoke(token, true)}
              >
                Revoke the chain
              </button>
            {/if}
          </span>
        </div>

        <div class="flex flex-wrap gap-1">
          {#each token.scopes as scope (scope)}
            <span class="scope" class:scope-privileged={scope.startsWith("masks:")}>{scope}</span>
          {/each}
        </div>

        <div class="flex flex-wrap gap-x-4 text-xs opacity-60">
          {#if token.audience.length}
            <span class="truncate font-mono" title={joined(token.audience)}>
              {joined(token.audience)}
            </span>
          {/if}
          {#if token.device}
            <span class="truncate">{token.device.label}</span>
          {/if}
          <span title={moment(token.createdAt)}>Issued {since(token.createdAt)}</span>
          <span title={moment(token.expiresAt)}>Expires {since(token.expiresAt)}</span>
        </div>
      </li>
    {/each}
  </ul>
{/if}
