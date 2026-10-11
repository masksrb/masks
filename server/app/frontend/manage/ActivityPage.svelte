<script>
  import ActivityParts from "./ActivityParts.svelte";
  import Tip from "./ui/Tip.svelte";
  import { t } from "./lib/copy.js";
  import { createPages } from "./lib/pages.svelte.js";
  import Pager from "./ui/Pager.svelte";
  import { untrack } from "svelte";
  import Events from "./Events.svelte";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { useRouter } from "./lib/router.svelte.js";
  import Section from "./ui/Section.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api } = $props();

  const pages = createPages();

  const FIELDS = `
    id action label createdAt ipAddress userAgent details
    actor { uuid identifier }
    by { uuid identifier }
    client { clientId name }
    device { id label }
  `;

  const QUERY = `
    query Activity(
      $action: String, $grave: Boolean, $afterId: ID, $limit: Int,
      $actor: ID, $client: ID
    ) {
      events(
        action: $action, grave: $grave, afterId: $afterId, limit: $limit,
        actor: $actor, client: $client
      ) { ${FIELDS} }
      eventCount(action: $action, grave: $grave, actor: $actor, client: $client)
      eventActions { action label }
    }
  `;

  const ABOUT_ACTOR = `query About($uuid: ID!) { actor(uuid: $uuid) { uuid identifier } }`;
  const ABOUT_CLIENT = `query About($clientId: ID!) { client(clientId: $clientId) { clientId name } }`;

  const feedback = createFeedback();
  const router = useRouter();

  let events = $state([]);
  let actions = $state([]);
  let exporting = $state(false);

  const today = () => new Date().toISOString().slice(0, 10);
  const daysAgo = (days) => new Date(Date.now() - days * 86400000).toISOString().slice(0, 10);

  let range = $state({ from: daysAgo(30), to: today() });
  let action = $state("");
  let grave = $state(false);
  let loading = $state(true);
  let about = $state(null);

  const actorId = $derived(router.query.get("actor"));
  const clientId = $derived(router.query.get("client"));
  const narrowed = $derived(Boolean(actorId || clientId));

  async function load() {
    loading = true;

    const data = await feedback.attempt(() =>
      api.query(QUERY, {
        action: action || null,
        grave,
        afterId: pages.cursor,
        limit: pages.size,
        actor: actorId,
        client: clientId,
      }),
    );

    loading = false;

    if (!data) return;

    actions = data.eventActions;
    events = data.events;
    pages.counted(data.eventCount);
  }

  function turn(direction) {
    if (direction === "forward") pages.forward(events.at(-1)?.id);
    else pages.back();

    load();
  }

  async function describe() {
    about = null;

    if (actorId) {
      const data = await api.query(ABOUT_ACTOR, { uuid: actorId }).catch(() => null);

      if (data?.actor) {
        about = { label: data.actor.identifier, to: `/actors/${data.actor.uuid}`, noun: t("activity.nouns.actor") };
      }

      return;
    }

    if (!clientId) return;

    const data = await api.query(ABOUT_CLIENT, { clientId }).catch(() => null);

    if (data?.client) {
      about = { label: data.client.name, to: `/clients/${data.client.clientId}`, noun: t("activity.nouns.client") };
    }
  }

  $effect(() => {
    actorId;
    clientId;

    untrack(() => {
      pages.reset();
      load();
      describe();
    });
  });

  function filter(chosen) {
    action = chosen;
    pages.reset();
    load();
  }

  function only(worrying) {
    grave = worrying;
    if (worrying) action = "";
    pages.reset();
    load();
  }

  async function download() {
    exporting = true;

    const answer = await feedback.attempt(() =>
      api.query(
        `mutation Export($from: ISO8601DateTime!, $to: ISO8601DateTime!, $action: String, $actor: ID) {
          exportEvents(from: $from, to: $to, action: $action, actor: $actor) { url count }
        }`,
        {
          from: new Date(`${range.from}T00:00:00`).toISOString(),
          to: new Date(new Date(`${range.to}T00:00:00`).getTime() + 86400000).toISOString(),
          action: action || null,
          actor: actorId || null,
        },
      ),
    );

    exporting = false;

    if (!answer) return;

    feedback.say(t("activity.downloading", { count: answer.exportEvents.count }));
    location.assign(answer.exportEvents.url);
  }
</script>

<Page title={t("activity.title")}>
  <ActivityParts part="log" />

  <Notices feedback={feedback.state} />

  {#if narrowed}
    <div class="alert alert-info alert-soft flex-wrap items-center gap-3 text-sm" role="status">
      {#if about}
        <span>
          {t("activity.involves", { noun: about.noun })}
          <Link to={about.to} class="link font-medium">{about.label}</Link>{t("activity.involves_end")}
        </span>
      {:else}
        <span>{t(actorId ? "activity.gone.actor" : "activity.gone.client")}</span>
      {/if}

      <Link to="/activity" class="btn btn-sm">{t("activity.everything")}</Link>
    </div>
  {/if}

  <Section>
    <div class="flex flex-wrap items-end gap-4">
      <label class="flex flex-col gap-1.5">
        <span class="legend">{t("activity.show")}</span>
        <select
          class="select select-sm w-full max-w-xs"
          value={action}
          disabled={grave}
          onchange={(event) => filter(event.currentTarget.value)}
        >
          <option value="">{t("activity.all")}</option>
          {#each actions as one (one.action)}
            <option value={one.action}>{one.label}</option>
          {/each}
        </select>
      </label>

      <label class="flex items-center gap-2 pb-1 text-sm">
        <input
          type="checkbox"
          class="toggle toggle-sm"
          checked={grave}
          onchange={(event) => only(event.currentTarget.checked)}
        />
        {t("activity.grave")}
      </label>

      <div class="flex flex-col gap-1.5 md:ml-auto">
        <span class="legend flex items-center gap-2">
          {t("activity.export.title")}
          <Tip text={t("activity.export.lede")} label={t("activity.export.title")} />
        </span>
        <div class="flex flex-wrap items-center gap-2">
          <input class="input input-sm w-auto" type="date" aria-label={t("activity.export.from")} bind:value={range.from} max={range.to} />
          <span class="hint">–</span>
          <input class="input input-sm w-auto" type="date" aria-label={t("activity.export.through")} bind:value={range.to} min={range.from} max={today()} />
          <button type="button" class="btn btn-sm" disabled={exporting || !range.from || !range.to} onclick={download}>
            {t("activity.export.download")}
          </button>
        </div>
      </div>
    </div>
  </Section>

  {#if loading && events.length === 0}
    <Spinner />
  {:else}
    <Section>
      <Events
        {events}
        empty={grave ? t("activity.empty.grave") : t("activity.empty.plain")}
      />

      <Pager {pages} shown={events.length} busy={loading} onpage={turn} />
    </Section>
  {/if}
</Page>
