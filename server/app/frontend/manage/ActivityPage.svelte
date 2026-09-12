<script>
  import { untrack } from "svelte";
  import Events from "./Events.svelte";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { said } from "./lib/events.js";
  import { useRouter } from "./lib/router.svelte.js";
  import Card from "./ui/Card.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api } = $props();

  const PAGE = 50;

  const FIELDS = `
    id action createdAt ipAddress userAgent details
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
      eventActions
    }
  `;

  const ABOUT_ACTOR = `query About($uuid: ID!) { actor(uuid: $uuid) { uuid identifier } }`;
  const ABOUT_CLIENT = `query About($clientId: ID!) { client(clientId: $clientId) { clientId name } }`;

  const feedback = createFeedback();
  const router = useRouter();

  let events = $state([]);
  let actions = $state([]);
  let action = $state("");
  let grave = $state(false);
  let loading = $state(true);
  let more = $state(false);
  let exhausted = $state(false);
  let about = $state(null);

  const actorId = $derived(router.query.get("actor"));
  const clientId = $derived(router.query.get("client"));
  const narrowed = $derived(Boolean(actorId || clientId));

  async function load(afterId = null) {
    if (afterId) more = true;
    else loading = true;

    const data = await feedback.attempt(() =>
      api.query(QUERY, {
        action: action || null,
        grave,
        afterId,
        limit: PAGE,
        actor: actorId,
        client: clientId,
      }),
    );

    loading = false;
    more = false;

    if (!data) return;

    actions = data.eventActions;
    events = afterId ? [...events, ...data.events] : data.events;
    exhausted = data.events.length < PAGE;
  }

  async function describe() {
    about = null;

    if (actorId) {
      const data = await api.query(ABOUT_ACTOR, { uuid: actorId }).catch(() => null);

      if (data?.actor) {
        about = { label: data.actor.identifier, to: `/people/${data.actor.uuid}`, noun: "person" };
      }

      return;
    }

    if (!clientId) return;

    const data = await api.query(ABOUT_CLIENT, { clientId }).catch(() => null);

    if (data?.client) {
      about = { label: data.client.name, to: `/clients/${data.client.clientId}`, noun: "client" };
    }
  }

  $effect(() => {
    actorId;
    clientId;

    untrack(() => {
      exhausted = false;
      load();
      describe();
    });
  });

  function filter(chosen) {
    action = chosen;
    exhausted = false;
    load();
  }

  function only(worrying) {
    grave = worrying;
    if (worrying) action = "";
    exhausted = false;
    load();
  }

  const oldest = $derived(events.at(-1)?.id ?? null);
</script>

<Page
  title="Activity"
  lede="Every sign-in, credential change and administrative act, newest first."
>
  <Notices feedback={feedback.state} />

  {#if narrowed}
    <div class="alert alert-info alert-soft flex-wrap items-center gap-3 text-sm" role="status">
      {#if about}
        <span>
          Only what involves the {about.noun}
          <Link to={about.to} class="link font-medium">{about.label}</Link>.
        </span>
      {:else}
        <span>Only what involves one {actorId ? "person" : "client"}, which no longer exists.</span>
      {/if}

      <Link to="/activity" class="btn btn-sm">Show everything</Link>
    </div>
  {/if}

  <Card>
    <div class="flex flex-wrap items-end gap-4">
      <label class="flex flex-col gap-1.5">
        <span class="legend">Show</span>
        <select
          class="select select-sm w-full max-w-xs"
          value={action}
          disabled={grave}
          onchange={(event) => filter(event.currentTarget.value)}
        >
          <option value="">everything</option>
          {#each actions as one (one)}
            <option value={one}>{said(one)}</option>
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
        Only what is worth a look
      </label>
    </div>
  </Card>

  {#if loading && events.length === 0}
    <Spinner />
  {:else}
    <Card>
      <Events
        {events}
        empty={grave
          ? "Nothing worth a look. Refusals, replays and blocks would show here."
          : action
            ? "Nothing of that kind has happened yet."
            : "Nothing has happened yet."}
      />

      {#if !exhausted && events.length}
        <div>
          <button
            type="button"
            class="btn btn-ghost btn-sm"
            disabled={more}
            onclick={() => load(oldest)}
          >
            {more ? "Loading..." : "Show older"}
          </button>
        </div>
      {/if}
    </Card>
  {/if}
</Page>
