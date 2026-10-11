<script>
  import { t } from "./lib/copy.js";
  import { moment, since } from "./lib/format.js";
  import Section from "./ui/Section.svelte";
  import Link from "./ui/Link.svelte";
  import Row from "./ui/Row.svelte";
  import Search from "./ui/Search.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Table from "./ui/Table.svelte";

  let { api, feedback } = $props();

  const LENSES = [
    ["allowed", t("devices.lenses.allowed"), { blocked: false }],
    ["blocked", t("devices.lenses.blocked"), { blocked: true }],
    ["unattached", t("devices.lenses.unattached"), { unattached: true }],
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
    t("devices.columns.device"),
    { label: t("devices.columns.who"), hide: true },
    { label: t("devices.columns.ip_address"), hide: true },
    t("devices.columns.last_seen"),
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

  function outcome(count, spared) {
    const done = t(blocking ? "devices.blocked_count" : "devices.unblocked_count", { count });

    return spared ? t("devices.spared", { done }) : done;
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
        ? t("devices.refused", { done: outcome(answer.count, answer.spared), agent: variables.agent })
        : outcome(answer.count, answer.spared),
    );
  }

  const blockChosen = () =>
    bulk(
      { ids: [...chosen] },
      blocking
        ? t("devices.block_chosen_question", { count: chosen.size })
        : t("devices.unblock_chosen_question", { count: chosen.size }),
    );

  const blockMatching = () => {
    const question = t("devices.block_matching_question", { agent });

    return bulk({ agent, refuse }, refuse ? t("devices.block_matching_refuse", { question }) : question);
  };

  const nothing = $derived(
    lens === "blocked"
      ? t("devices.empty.blocked")
      : lens === "unattached"
        ? t("devices.empty.unattached")
        : t("devices.empty.allowed"),
  );
</script>

<div id="devices" bind:this={section} class="scroll-mt-20">
  <Section title={t("devices.title")}>
    {#snippet actions()}
      <Search
        bind:value={search}
        label={t("devices.filter_label")}
        placeholder="curl, python-requests"
        onsearch={filter}
      />
      <div class="range" role="group" aria-label={t("devices.which")}>
        {#each LENSES as [key, label] (key)}
          <button type="button" aria-pressed={lens === key} onclick={() => look(key)}>{label}</button>
        {/each}
      </div>
    {/snippet}

    {#if agent && blocking}
      <div class="alert alert-warning alert-soft flex-col items-start gap-2">
        <p class="text-sm">
          {t("devices.showing")} <code class="font-mono">{agent}</code>.
          <button type="button" class="link" onclick={clearFilter}>{t("devices.clear")}</button>
        </p>
        <label class="flex items-center gap-2 text-sm">
          <input type="checkbox" class="checkbox" bind:checked={refuse} />
          {t("devices.refuse_agent")}
        </label>
        <button
          type="button"
          class="btn btn-sm btn-error btn-outline"
          disabled={busy}
          onclick={blockMatching}
        >
          {t("devices.block_matching")}
        </button>
      </div>
    {:else if agent}
      <p class="text-sm opacity-85">
        {t("devices.showing_blocked")} <code class="font-mono">{agent}</code>.
        <button type="button" class="link" onclick={clearFilter}>{t("devices.clear")}</button>
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
          {chosen.size
            ? t("devices.chosen", { count: chosen.size })
            : t("devices.choose_all", { count: devices.length })}
        </label>
        {#if chosen.size}
          <button
            type="button"
            class="btn btn-sm {blocking ? 'btn-error btn-outline' : 'btn-outline'}"
            disabled={busy}
            onclick={blockChosen}
          >
            {t(blocking ? "devices.block_count" : "devices.unblock_count", { count: chosen.size })}
          </button>
        {/if}
        {#if devices.length === LIMIT}
          <span class="hint">{t("devices.newest", { count: LIMIT })}</span>
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
                  aria-label={t("devices.choose", { label: device.label })}
                  checked={chosen.has(device.id)}
                  onchange={() => toggle(device.id)}
                />
              </td>
              <td class="max-w-[18rem]">
                <Link to={`/actors/devices/${device.id}`} class="link link-hover font-medium">
                  {device.label}
                </Link>
                <div class="flex flex-wrap items-center gap-1.5">
                  <span class="truncate text-xs opacity-75">{device.category}</span>
                  {#if device.blockedAt}
                    <span class="badge badge-error badge-xs">{t("devices.blocked")}</span>
                  {:else if !device.known}
                    <span class="badge badge-warning badge-xs">{t("devices.unrecognised")}</span>
                  {/if}
                  {#if device.sessions.length}
                    <span class="badge badge-success badge-xs">{t("devices.signed_in")}</span>
                  {/if}
                </div>
                {#if agent && device.userAgent}
                  <div class="truncate font-mono text-xs opacity-80" title={device.userAgent}>
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
                  <span class="opacity-80">{t("devices.nobody_yet")}</span>
                {/if}
              </td>

              <td class="hidden font-mono text-xs opacity-85 md:table-cell">
                {device.ipAddress ?? "—"}
              </td>

              <td class="text-xs whitespace-nowrap opacity-85" title={moment(device.lastSeenAt)}>
                {since(device.lastSeenAt)}
              </td>
            </Row>
          {/each}
        {/snippet}
      </Table>
    {/if}
  </Section>
</div>
