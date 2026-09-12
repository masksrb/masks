<script>
  import { moment, since } from "./lib/format.js";
  import Link from "./ui/Link.svelte";

  let { api, feedback, rows, onchange, showActor = false } = $props();

  const REVOKE = `
    mutation Revoke($id: ID!) {
      revokeConnection(id: $id) { connection { id revokedAt } }
    }
  `;

  async function revoke(connection) {
    const held = showActor ? connection.actor.identifier : connection.provider.name;

    if (
      !confirm(
        `Disconnect ${held}? The upstream tokens are handed back and any client holding ` +
          `${connection.provider.releaseScope} stops being released one.`,
      )
    )
      return;

    const done = await feedback.attempt(
      () => api.query(REVOKE, { id: connection.id }),
      "Disconnected.",
    );

    if (done) await onchange();
  }
</script>

{#if rows.length === 0}
  <p class="text-sm opacity-70">Nothing connected.</p>
{:else}
  <ul class="flex flex-col gap-1.5">
    {#each rows as connection (connection.id)}
      <li class="slat">
        <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
          <span class="flex flex-wrap items-baseline gap-2">
            {#if showActor}
              <Link to={`/people/${connection.actor.uuid}`} class="link link-hover text-sm font-medium">
                {connection.actor.identifier}
              </Link>
            {:else}
              <span class="text-sm font-medium">{connection.provider.name}</span>
            {/if}

            {#if connection.signedInAt}
              <span class="badge badge-success badge-xs">signs in</span>
            {/if}
            {#if connection.email && !connection.emailVerified}
              <span class="badge badge-warning badge-xs">unconfirmed</span>
            {/if}
          </span>

          <button type="button" class="link text-xs text-error" onclick={() => revoke(connection)}>
            Disconnect
          </button>
        </div>

        <span class="truncate text-xs opacity-45">
          {connection.label ?? connection.email ?? connection.subject}
        </span>

        <div class="flex flex-wrap gap-x-4 text-xs opacity-60">
          <span class="font-mono">{connection.provider.releaseScope}</span>
          <span title={moment(connection.connectedAt)}>
            Connected {since(connection.connectedAt)}
          </span>
          {#if connection.signedInAt}
            <span title={moment(connection.signedInAt)}>
              Signed in {since(connection.signedInAt)}
            </span>
          {/if}
        </div>
      </li>
    {/each}
  </ul>
{/if}
