<script>
  import { t } from "./lib/copy.js";
  import { detailed, tone } from "./lib/events.js";
  import { moment, since } from "./lib/format.js";
  import Link from "./ui/Link.svelte";

  let { events, showActor = true, empty = t("events.empty"), limit = 5, collapse = false } = $props();

  let all = $state(false);

  const same = (one, other) =>
    one.action === other.action &&
    one.actor?.uuid === other.actor?.uuid &&
    one.client?.clientId === other.client?.clientId;

  const runs = $derived(
    events.reduce((held, event) => {
      const last = held.at(-1);

      if (collapse && last && same(last.event, event)) last.count += 1;
      else held.push({ event, count: 1 });

      return held;
    }, []),
  );

  const shown = $derived(all ? runs : runs.slice(0, limit));

  const UUID = /\b([0-9a-f]{8})-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi;

  const trail = (event) =>
    [
      ...detailed(event.details).map(([key, value]) => `${key} ${value.replace(UUID, "$1…")}`),
      event.ipAddress,
      event.device?.label,
    ].filter(Boolean);
</script>

{#if events.length === 0}
  <p class="text-sm opacity-80">{empty}</p>
{:else}
  <ol class="slats">
    {#each shown as { event, count } (event.id)}
      <li class="event">
        <span class="event-what">
          <span
            class="event-label"
            class:text-error={tone(event.action) === "bad"}
            class:text-warning={tone(event.action) === "watch"}
            title={event.action}
          >{event.label}</span>

          {#if count > 1}
            <span class="event-count">{t("events.repeated", { count })}</span>
          {/if}

          {#if showActor && event.actor}
            <Link to={`/actors/${event.actor.uuid}`} class="link link-hover">{event.actor.identifier}</Link>
          {/if}

          {#if event.by && event.by.uuid !== event.actor?.uuid}
            <span class="hint">
              {t("events.by")}
              <Link to={`/actors/${event.by.uuid}`} class="link link-hover">{event.by.identifier}</Link>
            </span>
          {/if}

          {#if event.client}
            <Link to={`/clients/${event.client.clientId}`} class="badge badge-ghost badge-xs">{event.client.name}</Link>
          {/if}
        </span>

        <time class="event-when" datetime={event.createdAt} title={moment(event.createdAt)}>
          {since(event.createdAt)}
        </time>

        {#if trail(event).length}
          <span class="event-trail" title={JSON.stringify(event.details)}>{trail(event).join(" · ")}</span>
        {/if}
      </li>
    {/each}
  </ol>

  {#if !all && runs.length > limit}
    <button type="button" class="btn btn-ghost btn-sm self-start" onclick={() => (all = true)}>
      {t("events.more", { count: runs.length - limit })}
    </button>
  {/if}
{/if}
