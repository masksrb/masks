<script>
  import { t } from "./lib/copy.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import Section from "./ui/Section.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";

  let { api, rows, onreleased, showClient = false, row = false } = $props();

  const RELEASE = `
    mutation Release($name: String!) {
      releaseNamespace(name: $name) { released }
    }
  `;

  const feedback = createFeedback();

  async function release(held) {
    if (
      !confirm(t("namespaces.release_confirm", { name: held.name }))
    )
      return;

    const done = await feedback.attempt(
      () => api.query(RELEASE, { name: held.name }),
      t("namespaces.released", { name: held.name }),
    );

    if (done) await onreleased();
  }
</script>

<Section {row} title={t("namespaces.title")}>
  <Notices feedback={feedback.state} />

  <ul class="compact-list">
    {#each rows as held (held.name)}
      <li class="flex-wrap">
        <div class="flex min-w-0 flex-col">
          <span class="text-sm">
            <code class="font-mono">{held.name}</code>
            {#if showClient}
              <span class="hint">
                ·
                {#if held.client}
                  <Link to={`/clients/${held.client.clientId}`} class="link link-hover">{held.client.name}</Link>
                {:else}
                  {t("namespaces.nothing")}
                {/if}
              </span>
            {/if}
          </span>
          <span class="hint truncate text-xs"><span class="font-mono" title={held.resource}>{held.resource}</span> · {day(held.claimedAt)}</span>
        </div>

        <div class="ml-auto">
          {#if held.releasable}
            <button type="button" class="btn btn-xs btn-error btn-outline" onclick={() => release(held)}>
              {t("namespaces.release")}
            </button>
          {:else}
            <span class="hint text-xs">{t("namespaces.archive_to_release")}</span>
          {/if}
        </div>
      </li>
    {/each}
  </ul>
</Section>
