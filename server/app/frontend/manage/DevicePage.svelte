<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, moment, since } from "./lib/format.js";
  import Events from "./Events.svelte";
  import Card from "./ui/Card.svelte";
  import Facts from "./ui/Facts.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api, id } = $props();

  const QUERY = `
    query Device($id: ID!) {
      device(id: $id) {
        id label name category known ipAddress userAgent lastSeenAt blockedAt createdAt
        actors { uuid identifier }
        sessions {
          id ipAddress userAgent authenticatedAt expiresAt
          actor { uuid identifier }
        }
      }
      events(device: $id, limit: 25) {
        id action createdAt ipAddress details
        actor { uuid identifier }
        by { uuid identifier }
        client { clientId name }
      }
    }
  `;

  const feedback = createFeedback();

  let device = $state(null);
  let events = $state([]);
  let loading = $state(true);

  async function load() {
    loading = true;

    try {
      const data = await api.query(QUERY, { id });

      device = data.device;
      events = data.events;
    } catch (thrown) {
      feedback.blame(thrown);
    } finally {
      loading = false;
    }
  }

  load();

  async function act(mutation, notice, question = null) {
    if (question && !confirm(question)) return;

    const done = await feedback.attempt(
      () => api.query(`mutation Act($id: ID!) { ${mutation}(id: $id) { device { id } } }`, { id }),
      notice,
    );

    if (done) await load();
  }

  const block = () =>
    act(
      "blockDevice",
      `${device.label} is blocked.`,
      `Block ${device.label}? It is refused before any password is checked.`,
    );

  const unblock = () => act("unblockDevice", `${device.label} is unblocked.`);

  const signOut = () =>
    act(
      "signOutDevice",
      `Signed ${device.label} out everywhere.`,
      `Sign every account out of ${device.label}?`,
    );

  const facts = $derived(
    device
      ? [
          { term: "Kind", value: device.category },
          { term: "Address", value: device.ipAddress, mono: true },
          { term: "User agent", value: device.userAgent, mono: true },
          { term: "First seen", value: day(device.createdAt) },
          { term: "Last seen", value: moment(device.lastSeenAt) },
        ]
      : [],
  );
</script>

{#if loading && !device}
  <Spinner />
{:else if !device}
  <div class="alert alert-error alert-soft text-sm" role="alert">
    {feedback.state.failure ?? "There is no device with that id."}
  </div>
{:else}
  <Page
    title={device.label}
    id={device.id}
    back={{ to: "/devices", label: "Devices" }}
    lede={device.blockedAt
      ? `Blocked on ${day(device.blockedAt)}. Nobody can sign in on it.`
      : `Last seen ${since(device.lastSeenAt)}.`}
  >
    <Notices feedback={feedback.state} />

    <div class="grid items-start gap-4 md:grid-cols-2">
      <Card title="What it is">
        <Facts rows={facts} />

        <div class="flex flex-wrap gap-2 pt-1">
          {#if device.sessions.length}
            <button type="button" class="btn btn-sm" onclick={signOut}>Sign out everywhere</button>
          {/if}

          {#if device.blockedAt}
            <button type="button" class="btn btn-sm" onclick={unblock}>Unblock</button>
          {:else}
            <button type="button" class="btn btn-sm btn-error btn-outline" onclick={block}>
              Block
            </button>
          {/if}
        </div>
      </Card>

      <div class="flex flex-col gap-4">
        <Card title="Who signs in on it">
          {#if device.actors.length === 0}
            <p class="text-sm opacity-70">Nobody has signed in on it.</p>
          {:else}
            <ul class="flex flex-col gap-1.5">
              {#each device.actors as actor (actor.uuid)}
                <li class="slat">
                  <Link to={`/people/${actor.uuid}`} class="link link-hover text-sm font-medium">
                    {actor.identifier}
                  </Link>
                </li>
              {/each}
            </ul>
          {/if}
        </Card>

        <Card title="Live sessions">
          {#if device.sessions.length === 0}
            <p class="text-sm opacity-70">Nobody is signed in on it right now.</p>
          {:else}
            <ul class="flex flex-col gap-1.5">
              {#each device.sessions as session (session.id)}
                <li class="slat">
                  <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                    <Link
                      to={`/people/${session.actor.uuid}`}
                      class="link link-hover text-sm font-medium"
                    >
                      {session.actor.identifier}
                    </Link>
                    <span class="font-mono text-xs opacity-60">{session.ipAddress ?? "—"}</span>
                  </div>

                  <div class="flex flex-wrap gap-x-4 text-xs opacity-60">
                    <span title={moment(session.authenticatedAt)}>
                      Signed in {since(session.authenticatedAt)}
                    </span>
                    <span>Expires {day(session.expiresAt)}</span>
                  </div>
                </li>
              {/each}
            </ul>
          {/if}
        </Card>

        <Card title="Activity" lede="What has happened on this device, newest first.">
          <Events {events} empty="Nothing recorded on it yet." />
        </Card>
      </div>
    </div>
  </Page>
{/if}
