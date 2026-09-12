<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { moment, since } from "./lib/format.js";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Row from "./ui/Row.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Table from "./ui/Table.svelte";

  let { api } = $props();

  const LENSES = [
    ["allowed", "Allowed", { blocked: false }],
    ["blocked", "Blocked", { blocked: true }],
    ["unattached", "Never signed in", { unattached: true }],
  ];

  const QUERY = `
    query Devices($blocked: Boolean, $unattached: Boolean, $limit: Int) {
      devices(blocked: $blocked, unattached: $unattached, limit: $limit) {
        id label category known ipAddress userAgent lastSeenAt blockedAt
        actors { uuid identifier }
        sessions { id }
      }
    }
  `;

  const COLUMNS = [
    "Device",
    { label: "Who signs in on it", hide: true },
    { label: "Address", hide: true },
    "Last seen",
  ];

  const feedback = createFeedback();

  let devices = $state([]);
  let loading = $state(true);
  let lens = $state("allowed");

  const narrowing = $derived(LENSES.find(([key]) => key === lens)?.[2] ?? {});

  async function load() {
    loading = true;

    const data = await feedback.attempt(() =>
      api.query(QUERY, {
        blocked: narrowing.blocked ?? null,
        unattached: narrowing.unattached ?? null,
        limit: 100,
      }),
    );

    loading = false;

    if (data) devices = data.devices;
  }

  load();

  function look(chosen) {
    lens = chosen;
    load();
  }

  const nothing = $derived(
    lens === "blocked"
      ? "Nothing is blocked."
      : lens === "unattached"
        ? "Every device here has signed somebody in."
        : "No device has reached this server yet.",
  );
</script>

<Page
  title="Devices"
  lede="Every browser that has reached this server. Blocking one refuses it before a password is checked."
>
  {#snippet actions()}
    <div class="range" role="group" aria-label="Which devices">
      {#each LENSES as [key, label] (key)}
        <button type="button" aria-pressed={lens === key} onclick={() => look(key)}>{label}</button>
      {/each}
    </div>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if loading && devices.length === 0}
    <Spinner />
  {:else}
    <Table columns={COLUMNS} count={devices.length} empty={nothing}>
      {#snippet rows()}
        {#each devices as device (device.id)}
          <Row to={`/devices/${device.id}`}>
            <td class="max-w-[18rem]">
              <Link to={`/devices/${device.id}`} class="link link-hover font-medium">
                {device.label}
              </Link>
              <div class="flex flex-wrap items-center gap-1.5">
                <span class="truncate text-xs opacity-50">{device.category}</span>
                {#if device.blockedAt}
                  <span class="badge badge-error badge-xs">blocked</span>
                {:else if !device.known}
                  <span class="badge badge-warning badge-xs">unrecognised</span>
                {/if}
                {#if device.sessions.length}
                  <span class="badge badge-success badge-xs">signed in</span>
                {/if}
              </div>
            </td>

            <td class="hidden max-w-[16rem] text-xs md:table-cell">
              {#if device.actors.length}
                <div class="truncate">
                  {#each device.actors as actor, at (actor.uuid)}{at ? ", " : ""}<Link
                      to={`/people/${actor.uuid}`}
                      class="link link-hover">{actor.identifier}</Link
                    >{/each}
                </div>
              {:else}
                <span class="opacity-60">nobody yet</span>
              {/if}
            </td>

            <td class="hidden font-mono text-xs opacity-70 md:table-cell">
              {device.ipAddress ?? "—"}
            </td>

            <td class="text-xs whitespace-nowrap opacity-70" title={moment(device.lastSeenAt)}>
              {since(device.lastSeenAt)}
            </td>
          </Row>
        {/each}
      {/snippet}
    </Table>
  {/if}
</Page>
