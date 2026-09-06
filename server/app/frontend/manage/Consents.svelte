<script>
  import { joined, moment, since } from "./lib/format.js";
  import Link from "./ui/Link.svelte";

  let { api, feedback, rows, onchange, showActor = false } = $props();

  const REVOKE = `
    mutation Revoke($id: ID!) {
      revokeConsent(id: $id) { consent { id revokedAt } }
    }
  `;

  async function revoke(consent) {
    const held = showActor ? consent.actor.nickname : consent.client.name;

    if (
      !confirm(
        `Cut ${held} off? Every refresh token it holds is revoked, and it has to ask ` +
          `again the next time somebody signs in.`,
      )
    )
      return;

    const done = await feedback.attempt(
      () => api.query(REVOKE, { id: consent.id }),
      "Cut off. It will have to ask again.",
    );

    if (done) await onchange();
  }
</script>

{#if rows.length === 0}
  <p class="text-sm opacity-70">Nothing has been allowed in.</p>
{:else}
  <ul class="flex flex-col gap-1.5">
    {#each rows as consent (consent.id)}
      <li class="slat">
        <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
          {#if showActor}
            <Link to={`/people/${consent.actor.uuid}`} class="link link-hover text-sm font-medium">
              {consent.actor.nickname}
            </Link>
          {:else}
            <Link
              to={`/clients/${consent.client.clientId}`}
              class="link link-hover text-sm font-medium"
            >
              {consent.client.name}
            </Link>
          {/if}

          <button type="button" class="link text-xs text-error" onclick={() => revoke(consent)}>
            Cut off
          </button>
        </div>

        <div class="flex flex-wrap gap-1">
          {#each consent.scopes as scope (scope)}
            <span class="scope" class:scope-privileged={scope.startsWith("masks:")}>{scope}</span>
          {/each}
        </div>

        <div class="flex flex-wrap gap-x-4 text-xs opacity-60">
          {#if consent.audience.length}
            <span class="truncate font-mono" title={joined(consent.audience)}>
              {joined(consent.audience)}
            </span>
          {/if}
          <span title={moment(consent.updatedAt)}>Last asked {since(consent.updatedAt)}</span>
        </div>
      </li>
    {/each}
  </ul>
{/if}
