<script>
  import Events from "./Events.svelte";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { said } from "./lib/events.js";
  import Card from "./ui/Card.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api } = $props();

  const PAGE = 50;

  const FIELDS = `
    id action createdAt ipAddress userAgent details
    actor { uuid nickname }
    by { uuid nickname }
    client { clientId name }
    device { id label }
  `;

  const QUERY = `
    query Activity($action: String, $before: ISO8601DateTime, $limit: Int) {
      events(action: $action, before: $before, limit: $limit) { ${FIELDS} }
      eventActions
    }
  `;

  const feedback = createFeedback();

  let events = $state([]);
  let actions = $state([]);
  let action = $state("");
  let loading = $state(true);
  let more = $state(false);
  let exhausted = $state(false);

  async function load(before = null) {
    if (before) more = true;
    else loading = true;

    const data = await feedback.attempt(() =>
      api.query(QUERY, { action: action || null, before, limit: PAGE }),
    );

    loading = false;
    more = false;

    if (!data) return;

    actions = data.eventActions;
    events = before ? [...events, ...data.events] : data.events;
    exhausted = data.events.length < PAGE;
  }

  load();

  function filter(chosen) {
    action = chosen;
    exhausted = false;
    load();
  }

  const oldest = $derived(events.at(-1)?.createdAt ?? null);
</script>

<Page
  title="Activity"
  lede="Every sign-in, credential change and administrative act, newest first."
>
  <Notices feedback={feedback.state} />

  <Card>
    <label class="flex flex-col gap-1.5">
      <span class="legend">Show</span>
      <select
        class="select select-sm w-full max-w-xs"
        value={action}
        onchange={(event) => filter(event.currentTarget.value)}
      >
        <option value="">everything</option>
        {#each actions as one (one)}
          <option value={one}>{said(one)}</option>
        {/each}
      </select>
    </label>
  </Card>

  {#if loading && events.length === 0}
    <Spinner />
  {:else}
    <Card>
      <Events
        {events}
        empty={action ? "Nothing of that kind has happened yet." : "Nothing has happened yet."}
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
