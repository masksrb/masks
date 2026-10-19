<script>
  import { t } from "./lib/copy.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import Section from "./ui/Section.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";

  let { api, rows, onrevoked } = $props();

  const UNENROLL = `
    mutation Unenroll($clientId: ID!) {
      unenrollClient(clientId: $clientId) { client { archivedAt } }
    }
  `;

  const feedback = createFeedback();

  async function revoke(machine) {
    if (!confirm(t("machines.revoke_confirm", { name: machine.name }))) return;

    const done = await feedback.attempt(
      () => api.query(UNENROLL, { clientId: machine.clientId }),
      t("machines.revoked", { name: machine.name }),
    );

    if (done) await onrevoked();
  }
</script>

<Section title={t("machines.title")} lede={t("machines.lede")}>
  <Notices feedback={feedback.state} />

  {#if rows.length}
    <ul class="compact-list">
      {#each rows as machine (machine.clientId)}
        <li class="flex-wrap">
          <div class="flex min-w-0 flex-col">
            <span class="text-sm">
              <Link to={`/clients/${machine.clientId}`} class="link link-hover">{machine.name}</Link>
            </span>
            <span class="hint truncate text-xs">
              <span class="font-mono">{machine.clientId}</span>
              · {machine.lastSeenAt ? t("machines.last_seen", { day: day(machine.lastSeenAt) }) : t("machines.never")}
              · {t("machines.enrolled", { day: day(machine.createdAt) })}
            </span>
          </div>

          <div class="ml-auto">
            <button type="button" class="btn btn-xs btn-error btn-outline" onclick={() => revoke(machine)}>
              {t("machines.revoke")}
            </button>
          </div>
        </li>
      {/each}
    </ul>
  {:else}
    <p class="text-sm opacity-85">{t("machines.empty")}</p>
  {/if}
</Section>
