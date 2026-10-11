<script>
  import { t } from "./lib/copy.js";
  import { detailed, tone } from "./lib/events.js";
  import { moment, since } from "./lib/format.js";
  import Link from "./ui/Link.svelte";

  let { events, showActor = true, empty = t("events.empty"), limit = 5 } = $props();

  let all = $state(false);

  const shown = $derived(all ? events : events.slice(0, limit));
</script>

{#if events.length === 0}
  <p class="text-sm opacity-80">{empty}</p>
{:else}
  <ol class="slats">
    {#each shown as event (event.id)}
      <li class="slat">
        <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
          <span class="flex flex-wrap items-baseline gap-2">
            <span
              class="text-sm font-medium"
              class:text-error={tone(event.action) === "bad"}
              class:text-warning={tone(event.action) === "watch"}
              title={event.action}
            >{event.label}</span>

            {#if showActor && event.actor}
              <Link to={`/actors/${event.actor.uuid}`} class="link link-hover text-xs">
                {event.actor.identifier}
              </Link>
            {/if}

            {#if event.by && event.by.uuid !== event.actor?.uuid}
              <span class="hint">
                {t("events.by")}
                <Link to={`/actors/${event.by.uuid}`} class="link link-hover">
                  {event.by.identifier}
                </Link>
              </span>
            {/if}

            {#if event.client}
              <Link to={`/clients/${event.client.clientId}`} class="badge badge-ghost badge-xs">
                {event.client.name}
              </Link>
            {/if}
          </span>

          <span class="text-xs whitespace-nowrap opacity-80" title={moment(event.createdAt)}>
            {since(event.createdAt)}
          </span>
        </div>

        {#if detailed(event.details).length}
          <div class="flex flex-wrap gap-x-4 text-xs opacity-80">
            {#each detailed(event.details) as [key, value] (key)}
              <span><span class="opacity-85">{key}</span> {value}</span>
            {/each}
          </div>
        {/if}

        {#if event.ipAddress || event.device}
          <div class="flex flex-wrap gap-x-4 text-xs opacity-75">
            {#if event.ipAddress}<span class="font-mono">{event.ipAddress}</span>{/if}
            {#if event.device}
              <span class="truncate">{event.device.label}</span>
            {/if}
          </div>
        {/if}
      </li>
    {/each}
  </ol>

  {#if !all && events.length > limit}
    <button type="button" class="btn btn-ghost btn-sm self-start" onclick={() => (all = true)}>
      {t("events.more", { count: events.length - limit })}
    </button>
  {/if}
{/if}
