<script>
  import { t } from "./lib/copy.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import Section from "./ui/Section.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";

  let { api, rows, labels, ondecided } = $props();

  const GRANT = `
    mutation GrantAccess($id: ID!, $label: String) {
      grantAccess(id: $id, label: $label) { accessRequest { id label } }
    }
  `;

  const DECLINE = `
    mutation DeclineAccess($id: ID!) {
      declineAccess(id: $id) { accessRequest { id } }
    }
  `;

  const feedback = createFeedback();
  let chosen = $state({});

  async function grant(request) {
    const label = chosen[request.id] ?? labels[0];
    const done = await feedback.attempt(
      () => api.query(GRANT, { id: request.id, label }),
      t("access_requests.granted", { identifier: request.actor.identifier, label }),
    );

    if (done) await ondecided();
  }

  async function decline(request) {
    const done = await feedback.attempt(
      () => api.query(DECLINE, { id: request.id }),
      t("access_requests.declined", { identifier: request.actor.identifier }),
    );

    if (done) await ondecided();
  }
</script>

<Section row title={t("access_requests.title")} lede={t("access_requests.lede")}>
  <Notices feedback={feedback.state} />

  {#if rows.length}
    <ul class="compact-list">
      {#each rows as request (request.id)}
        <li class="flex-wrap">
          <div class="flex min-w-0 flex-col">
            <span class="text-sm">
              <Link to={`/actors/${request.actor.uuid}`} class="link link-hover">{request.actor.identifier}</Link>
            </span>
            <span class="hint text-xs">{t("access_requests.asked", { day: day(request.createdAt) })}</span>
          </div>

          <div class="ml-auto flex flex-wrap items-center gap-2">
            {#if labels.length > 1}
              <select
                class="select select-xs"
                aria-label={t("access_requests.as")}
                value={chosen[request.id] ?? labels[0]}
                onchange={(event) => (chosen[request.id] = event.currentTarget.value)}
              >
                {#each labels as label (label)}
                  <option value={label}>{label}</option>
                {/each}
              </select>
            {/if}

            <button type="button" class="btn btn-xs btn-primary" onclick={() => grant(request)}>
              {t("access_requests.grant")}
            </button>
            <button type="button" class="btn btn-xs btn-outline" onclick={() => decline(request)}>
              {t("access_requests.decline")}
            </button>
          </div>
        </li>
      {/each}
    </ul>
  {:else}
    <p class="text-sm opacity-85">{t("access_requests.empty")}</p>
  {/if}
</Section>
