<script>
  import { t } from "./lib/copy.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import Section from "./ui/Section.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";

  let { api, rows, onreleased, showClient = false } = $props();

  const RELEASE = `
    mutation Release($name: String!) {
      releaseNamespace(name: $name) { released }
    }
  `;

  const feedback = createFeedback();

  async function release(row) {
    if (
      !confirm(t("namespaces.release_confirm", { name: row.name }))
    )
      return;

    const done = await feedback.attempt(
      () => api.query(RELEASE, { name: row.name }),
      t("namespaces.released", { name: row.name }),
    );

    if (done) await onreleased();
  }
</script>

<Section title={t("namespaces.title")}>
  <Notices feedback={feedback.state} />

  <div class="overflow-x-auto">
    <table class="table table-sm">
      <thead>
        <tr>
          <th>{t("namespaces.columns.name")}</th>
          {#if showClient}<th>{t("namespaces.columns.claimed_by")}</th>{/if}
          <th class="hidden sm:table-cell">{t("namespaces.columns.resource")}</th>
          <th class="hidden sm:table-cell">{t("namespaces.columns.claimed")}</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        {#each rows as row (row.name)}
          <tr>
            <td class="font-mono text-xs">{row.name}</td>

            {#if showClient}
              <td class="text-xs">
                {#if row.client}
                  <Link to={`/clients/${row.client.clientId}`} class="link link-hover">
                    {row.client.name}
                  </Link>
                {:else}
                  <span class="opacity-80">{t("namespaces.nothing")}</span>
                {/if}
              </td>
            {/if}

            <td class="hidden max-w-[18rem] font-mono text-xs opacity-85 sm:table-cell">
              <div class="truncate" title={row.resource}>{row.resource}</div>
            </td>

            <td class="hidden text-xs opacity-85 sm:table-cell">{day(row.claimedAt)}</td>

            <td class="text-right whitespace-nowrap">
              {#if row.releasable}
                <button
                  type="button"
                  class="btn btn-xs btn-error btn-outline"
                  onclick={() => release(row)}
                >
                  {t("namespaces.release")}
                </button>
              {:else}
                <span class="hint">{t("namespaces.archive_to_release")}</span>
              {/if}
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
</Section>
