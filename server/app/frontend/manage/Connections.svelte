<script>
  import { t } from "./lib/copy.js";
  import { moment, since } from "./lib/format.js";
  import Link from "./ui/Link.svelte";

  let { api, feedback, rows, onchange, showActor = false } = $props();

  const REVOKE = `
    mutation Revoke($id: ID!) {
      revokeConnection(id: $id) { connection { id revokedAt } }
    }
  `;

  const STOP = `
    mutation Stop($id: ID!) {
      revokeDelegation(id: $id) { delegation { id revokedAt } }
    }
  `;

  async function stop(connection, delegation) {
    if (!confirm(t("connections.stop_confirm", { client: delegation.client.name, provider: connection.provider.name })))
      return;

    const done = await feedback.attempt(
      () => api.query(STOP, { id: delegation.id }),
      t("connections.stopped", { client: delegation.client.name }),
    );

    if (done) await onchange();
  }

  async function revoke(connection) {
    const held = showActor ? connection.actor.identifier : connection.provider.name;

    if (
      !confirm(t("connections.disconnect_confirm", { held }))
    )
      return;

    const done = await feedback.attempt(
      () => api.query(REVOKE, { id: connection.id }),
      t("connections.disconnected"),
    );

    if (done) await onchange();
  }
</script>

{#if rows.length === 0}
  <p class="text-sm opacity-85">{t("connections.empty")}</p>
{:else}
  <ul class="slats">
    {#each rows as connection (connection.id)}
      <li class="slat">
        <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
          <span class="flex flex-wrap items-baseline gap-2">
            {#if showActor}
              <Link to={`/actors/${connection.actor.uuid}`} class="link link-hover text-sm font-medium">
                {connection.actor.identifier}
              </Link>
            {:else}
              <span class="text-sm font-medium">{connection.provider.name}</span>
            {/if}

            {#if connection.signedInAt}
              <span class="badge badge-success badge-xs">{t("connections.badges.signs_in")}</span>
            {/if}
            {#if connection.email && !connection.emailVerified}
              <span class="badge badge-warning badge-xs">{t("connections.badges.unconfirmed")}</span>
            {/if}
            {#if connection.delegable}
              <span class="badge badge-info badge-xs">{t("connections.badges.delegable")}</span>
            {/if}
          </span>

          <button type="button" class="link text-xs text-error" onclick={() => revoke(connection)}>
            {t("connections.disconnect")}
          </button>
        </div>

        <span class="truncate text-xs opacity-75">
          {connection.label ?? connection.email ?? connection.subject}
        </span>

        <div class="flex flex-wrap gap-x-4 text-xs opacity-80">
          <span title={moment(connection.connectedAt)}>
            {t("connections.connected", { when: since(connection.connectedAt) })}
          </span>
          {#if connection.signedInAt}
            <span title={moment(connection.signedInAt)}>
              {t("connections.signed_in", { when: since(connection.signedInAt) })}
            </span>
          {/if}
        </div>

        {#each connection.delegations ?? [] as delegation (delegation.id)}
          <div class="flex flex-wrap items-baseline justify-between gap-x-3 border-l-2 border-base-300 pl-2 text-xs">
            <span>
              <Link to={`/clients/${delegation.client.clientId}`} class="link link-hover">{delegation.client.name}</Link>
              <span class="opacity-80">
                {delegation.releasedAt
                  ? t("connections.can_use_last", { when: since(delegation.releasedAt) })
                  : t("connections.can_use")}
              </span>
            </span>
            <button type="button" class="link text-error" onclick={() => stop(connection, delegation)}>{t("connections.stop")}</button>
          </div>
        {/each}
      </li>
    {/each}
  </ul>
{/if}
