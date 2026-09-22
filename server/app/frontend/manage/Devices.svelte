<script>
  import { moment, since } from "./lib/format.js";
  import Card from "./ui/Card.svelte";
  import Link from "./ui/Link.svelte";
  import Row from "./ui/Row.svelte";
  import Search from "./ui/Search.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Table from "./ui/Table.svelte";

  let { api, feedback } = $props();

  const LENSES = [
    ["allowed", "Allowed", { blocked: false }],
    ["blocked", "Blocked", { blocked: true }],
    ["unattached", "Never signed in", { unattached: true }],
  ];

  const QUERY = `
    query Devices($blocked: Boolean, $unattached: Boolean, $agent: String, $limit: Int) {
      devices(blocked: $blocked, unattached: $unattached, agent: $agent, limit: $limit) {
        id label category known ipAddress userAgent lastSeenAt blockedAt
        actors { uuid identifier }
        sessions { id }
      }
    }
  `;

  const LIMIT = 100;

  const COLUMNS = [
    "",
    "Device",
    { label: "Who signs in on it", hide: true },
    { label: "IP address", hide: true },
    "Last seen",
  ];

  let devices = $state([]);
  let loading = $state(true);
  let lens = $state("allowed");
  let search = $state("");
  let agent = $state("");
  let chosen = $state(new Set());
  let refuse = $state(false);
  let busy = $state(false);
  let section = $state(null);

  const narrowing = $derived(LENSES.find(([key]) => key === lens)?.[2] ?? {});

  async function load() {
    loading = true;

    const data = await feedback.attempt(() =>
      api.query(QUERY, {
        blocked: narrowing.blocked ?? null,
        unattached: narrowing.unattached ?? null,
        agent: agent || null,
        limit: LIMIT,
      }),
    );

    loading = false;

    if (data) {
      devices = data.devices;
      chosen = new Set();
    }
  }

  load().then(() => {
    if (location.hash === "#devices") section?.scrollIntoView();
  });

  function look(key) {
    lens = key;
    load();
  }

  function filter() {
    agent = search.trim();
    refuse = false;
    load();
  }

  function clearFilter() {
    search = "";
    filter();
  }

  function toggle(id) {
    const next = new Set(chosen);

    next.has(id) ? next.delete(id) : next.add(id);
    chosen = next;
  }

  const all = $derived(devices.length > 0 && chosen.size === devices.length);

  function toggleAll() {
    chosen = all ? new Set() : new Set(devices.map((device) => device.id));
  }

  const blocking = $derived(lens !== "blocked");
  const plural = (count) => `${count} device${count === 1 ? "" : "s"}`;

  function outcome(count, spared) {
    const done = `${blocking ? "Blocked" : "Unblocked"} ${plural(count)}.`;

    return spared ? `${done} The device you are using was left alone.` : done;
  }

  async function bulk(variables, question) {
    if (!confirm(question)) return;

    busy = true;

    const mutation = blocking
      ? `mutation Bulk($ids: [ID!], $agent: String, $refuse: Boolean) {
          blockDevices(ids: $ids, agent: $agent, refuse: $refuse) { count spared }
        }`
      : `mutation Bulk($ids: [ID!]!) { unblockDevices(ids: $ids) { count } }`;

    const data = await feedback.attempt(() => api.query(mutation, variables));

    busy = false;

    if (!data) return;

    const answer = data.blockDevices ?? data.unblockDevices;

    await load();
    feedback.say(
      refuse && variables.agent
        ? `${outcome(answer.count, answer.spared)} "${variables.agent}" is refused from now on.`
        : outcome(answer.count, answer.spared),
    );
  }

  const blockChosen = () =>
    bulk(
      { ids: [...chosen] },
      blocking
        ? `Block ${plural(chosen.size)}? Each is signed out and refused before any password is checked.`
        : `Unblock ${plural(chosen.size)}?`,
    );

  const blockMatching = () =>
    bulk(
      { agent, refuse },
      `Block every device whose user agent contains "${agent}", including any not listed here?${
        refuse ? ` New devices sending it are refused too.` : ""
      }`,
    );

  const nothing = $derived(
    lens === "blocked"
      ? "Nothing is blocked."
      : lens === "unattached"
        ? "Every device here has signed somebody in."
        : "No device has reached this server yet.",
  );
</script>

<div id="devices" bind:this={section} class="scroll-mt-20">
  <Card title="Devices">
    {#snippet actions()}
      <Search
        bind:value={search}
        label="Filter by user agent"
        placeholder="curl, python-requests"
        onsearch={filter}
      />
      <div class="range" role="group" aria-label="Which devices">
        {#each LENSES as [key, label] (key)}
          <button type="button" aria-pressed={lens === key} onclick={() => look(key)}>{label}</button>
        {/each}
      </div>
    {/snippet}

    {#if agent && blocking}
      <div class="alert alert-warning alert-soft flex-col items-start gap-2">
        <p class="text-sm">
          Showing devices whose user agent contains <code class="font-mono">{agent}</code>.
          <button type="button" class="link" onclick={clearFilter}>Clear</button>
        </p>
        <label class="flex items-center gap-2 text-sm">
          <input type="checkbox" class="checkbox" bind:checked={refuse} />
          Also refuse this user agent from now on
        </label>
        <button
          type="button"
          class="btn btn-sm btn-error btn-outline"
          disabled={busy}
          onclick={blockMatching}
        >
          Block every matching device
        </button>
      </div>
    {:else if agent}
      <p class="text-sm opacity-70">
        Showing blocked devices whose user agent contains <code class="font-mono">{agent}</code>.
        <button type="button" class="link" onclick={clearFilter}>Clear</button>
      </p>
    {/if}

    {#if devices.length}
      <div class="flex flex-wrap items-center gap-3">
        <label class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            class="checkbox"
            checked={all}
            indeterminate={chosen.size > 0 && !all}
            onchange={toggleAll}
          />
          {chosen.size ? `${chosen.size} chosen` : `Choose all ${plural(devices.length)} shown`}
        </label>
        {#if chosen.size}
          <button
            type="button"
            class="btn btn-sm {blocking ? 'btn-error btn-outline' : 'btn-outline'}"
            disabled={busy}
            onclick={blockChosen}
          >
            {blocking ? "Block" : "Unblock"} {plural(chosen.size)}
          </button>
        {/if}
        {#if devices.length === LIMIT}
          <span class="text-xs opacity-60">Only the newest {LIMIT} are shown.</span>
        {/if}
      </div>
    {/if}

    {#if loading && devices.length === 0}
      <Spinner />
    {:else}
      <Table columns={COLUMNS} count={devices.length} empty={nothing}>
        {#snippet rows()}
          {#each devices as device (device.id)}
            <Row to={`/actors/devices/${device.id}`}>
              <td class="w-0">
                <input
                  type="checkbox"
                  class="checkbox"
                  aria-label={`Choose ${device.label}`}
                  checked={chosen.has(device.id)}
                  onchange={() => toggle(device.id)}
                />
              </td>
              <td class="max-w-[18rem]">
                <Link to={`/actors/devices/${device.id}`} class="link link-hover font-medium">
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
                {#if agent && device.userAgent}
                  <div class="truncate font-mono text-xs opacity-60" title={device.userAgent}>
                    {device.userAgent}
                  </div>
                {/if}
              </td>

              <td class="hidden max-w-[16rem] text-xs md:table-cell">
                {#if device.actors.length}
                  <div class="truncate">
                    {#each device.actors as actor, at (actor.uuid)}{at ? ", " : ""}<Link
                        to={`/actors/${actor.uuid}`}
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
  </Card>
</div>
