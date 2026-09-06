<script>
  import { detailed, said, tone } from "./lib/events.js";
  import { moment, since } from "./lib/format.js";
  import Link from "./ui/Link.svelte";

  let { events, showActor = true, empty = "Nothing has happened yet." } = $props();
</script>

{#if events.length === 0}
  <p class="text-sm opacity-60">{empty}</p>
{:else}
  <ol class="flex flex-col gap-1.5">
    {#each events as event (event.id)}
      <li class="slat">
        <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
          <span class="flex flex-wrap items-baseline gap-2">
            <span
              class="text-sm font-medium"
              class:text-error={tone(event.action) === "bad"}
              class:text-warning={tone(event.action) === "watch"}
            >{said(event.action)}</span>

            {#if showActor && event.actor}
              <Link to={`/people/${event.actor.uuid}`} class="link link-hover text-xs">
                {event.actor.nickname}
              </Link>
            {/if}

            {#if event.by && event.by.uuid !== event.actor?.uuid}
              <span class="text-xs opacity-60">
                by <Link to={`/people/${event.by.uuid}`} class="link link-hover">
                  {event.by.nickname}
                </Link>
              </span>
            {/if}

            {#if event.client}
              <span class="badge badge-ghost badge-xs">{event.client.name}</span>
            {/if}
          </span>

          <span class="text-xs whitespace-nowrap opacity-60" title={moment(event.createdAt)}>
            {since(event.createdAt)}
          </span>
        </div>

        {#if detailed(event.details).length}
          <div class="flex flex-wrap gap-x-4 text-xs opacity-60">
            {#each detailed(event.details) as [key, value] (key)}
              <span><span class="opacity-70">{key}</span> {value}</span>
            {/each}
          </div>
        {/if}

        <div class="flex flex-wrap gap-x-4 text-xs opacity-45">
          <span class="font-mono">{event.ipAddress ?? "—"}</span>
          {#if event.device}
            <span class="truncate">{event.device.label}</span>
          {/if}
          <span class="font-mono opacity-70">{event.action}</span>
        </div>
      </li>
    {/each}
  </ol>
{/if}
