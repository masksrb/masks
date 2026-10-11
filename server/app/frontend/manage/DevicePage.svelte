<script>
  import { t } from "./lib/copy.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, moment, since } from "./lib/format.js";
  import Events from "./Events.svelte";
  import Section from "./ui/Section.svelte";
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
        id action label createdAt ipAddress details
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
      t("device.blocked", { label: device.label }),
      t("device.block_question", { label: device.label }),
    );

  const unblock = () => act("unblockDevice", t("device.unblocked", { label: device.label }));

  const signOut = () =>
    act(
      "signOutDevice",
      t("device.signed_out", { label: device.label }),
      t("device.sign_out_question", { label: device.label }),
    );

  const facts = $derived(
    device
      ? [
          { term: t("device.facts.kind"), value: device.category },
          { term: t("device.facts.ip_address"), value: device.ipAddress, mono: true },
          { term: t("device.facts.user_agent"), value: device.userAgent, mono: true },
          { term: t("device.facts.first_seen"), value: day(device.createdAt) },
          { term: t("device.facts.last_seen"), value: moment(device.lastSeenAt) },
        ]
      : [],
  );
</script>

{#if loading && !device}
  <Spinner />
{:else if !device}
  <div class="alert alert-error alert-soft text-sm" role="alert">
    {feedback.state.failure ?? t("device.missing")}
  </div>
{:else}
  <Page
    title={device.label}
    id={device.id}
    back={{ to: "/actors#devices", label: t("device.back") }}
    lede={device.blockedAt
      ? t("device.blocked_lede", { day: day(device.blockedAt) })
      : t("device.seen_lede", { when: since(device.lastSeenAt) })}
  >
    <Notices feedback={feedback.state} />

    <div class="grid items-start gap-4 md:grid-cols-2">
      <Section title={t("device.what")}>
        <Facts rows={facts} />

        <div class="flex flex-wrap gap-2 pt-1">
          {#if device.sessions.length}
            <button type="button" class="btn btn-sm" onclick={signOut}>{t("device.sign_out_everywhere")}</button>
          {/if}

          {#if device.blockedAt}
            <button type="button" class="btn btn-sm" onclick={unblock}>{t("device.unblock")}</button>
          {:else}
            <button type="button" class="btn btn-sm btn-error btn-outline" onclick={block}>
              {t("device.block")}
            </button>
          {/if}
        </div>
      </Section>

      <div class="flex flex-col gap-4">
        <Section title={t("device.who")}>
          {#if device.actors.length === 0}
            <p class="text-sm opacity-85">{t("device.nobody")}</p>
          {:else}
            <ul class="slats">
              {#each device.actors as actor (actor.uuid)}
                <li class="slat">
                  <Link to={`/actors/${actor.uuid}`} class="link link-hover text-sm font-medium">
                    {actor.identifier}
                  </Link>
                </li>
              {/each}
            </ul>
          {/if}
        </Section>

        <Section title={t("device.live_sessions")}>
          {#if device.sessions.length === 0}
            <p class="text-sm opacity-85">{t("device.no_sessions")}</p>
          {:else}
            <ul class="slats">
              {#each device.sessions as session (session.id)}
                <li class="slat">
                  <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                    <Link
                      to={`/actors/${session.actor.uuid}`}
                      class="link link-hover text-sm font-medium"
                    >
                      {session.actor.identifier}
                    </Link>
                    <span class="font-mono text-xs opacity-80">{session.ipAddress ?? "—"}</span>
                  </div>

                  <div class="flex flex-wrap gap-x-4 text-xs opacity-80">
                    <span title={moment(session.authenticatedAt)}>
                      {t("device.signed_in", { when: since(session.authenticatedAt) })}
                    </span>
                    <span>{t("device.expires", { when: day(session.expiresAt) })}</span>
                  </div>
                </li>
              {/each}
            </ul>
          {/if}
        </Section>

        <Section title={t("device.activity")}>
          <Events {events} empty={t("device.no_activity")} />
        </Section>
      </div>
    </div>
  </Page>
{/if}
