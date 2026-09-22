<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, joined, moment, since } from "./lib/format.js";
  import ScopesEditor from "./ScopesEditor.svelte";
  import Card from "./ui/Card.svelte";
  import Field from "./ui/Field.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Row from "./ui/Row.svelte";
  import Search from "./ui/Search.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Table from "./ui/Table.svelte";

  let { api } = $props();

  const PRESENCE = `
    sessions { id ipAddress userAgent authenticatedAt expiresAt }
    devices { id label category known ipAddress userAgent lastSeenAt blockedAt }
  `;

  const PAGE = 50;

  const LENSES = [
    ["everyone", "Everyone", {}],
    ["invited", "Invited", { activated: false }],
    ["waiting", "Awaiting approval", { pendingApproval: true }],
    ["managers", "Managers", { holds: "masks:manage" }],
    ["suspended", "Suspended", { suspended: true }],
  ];

  const QUERY = `
    query People(
      $search: String, $activated: Boolean, $holds: String, $pendingApproval: Boolean,
      $suspended: Boolean, $afterId: ID, $limit: Int
    ) {
      actors(
        search: $search, activated: $activated, holds: $holds, pendingApproval: $pendingApproval,
        suspended: $suspended, afterId: $afterId, limit: $limit
      ) {
        uuid identifier nickname name email emailVerified otpEnabled backupCodesRemaining
        lastLoginAt scopes activated invitedAt
        avatars { photo identicon }
        ${PRESENCE}
      }
    }
  `;

  const CREATE = `
    mutation Create($nickname: String, $email: String, $password: String, $scopes: [String!]) {
      createActor(nickname: $nickname, email: $email, password: $password, scopes: $scopes) {
        delivered url actor { uuid identifier activated }
      }
    }
  `;

  const STANDARD = ["openid", "profile", "email", "offline_access", "identities"];

  const COLUMNS = [
    "Person",
    { label: "Scopes", hide: true },
    { label: "Second factor", hide: true },
    { label: "Signed in on", hide: true },
    { label: "Last seen", hide: true },
  ];

  const feedback = createFeedback();

  let search = $state("");
  let people = $state([]);
  let loading = $state(true);
  let more = $state(false);
  let exhausted = $state(false);
  let lens = $state("everyone");

  const narrowing = $derived(LENSES.find(([key]) => key === lens)?.[2] ?? {});

  let adding = $state(false);
  let nickname = $state("");
  let email = $state("");
  let password = $state("");
  let scopes = $state([...STANDARD]);
  let supported = $state([]);
  let minimum = $state(8);
  let busy = $state(false);
  let created = $state(null);

  async function load(afterId = null) {
    if (afterId) more = true;
    else loading = true;

    try {
      const data = await api.query(QUERY, {
        search: search.trim() || null,
        activated: narrowing.activated ?? null,
        holds: narrowing.holds ?? null,
        pendingApproval: narrowing.pendingApproval ?? null,
        suspended: narrowing.suspended ?? null,
        afterId,
        limit: PAGE,
      });

      people = afterId ? [...people, ...data.actors] : data.actors;
      exhausted = data.actors.length < PAGE;
    } catch (thrown) {
      feedback.blame(thrown);
    } finally {
      loading = false;
      more = false;
    }
  }

  function again() {
    exhausted = false;
    load();
  }

  function look(chosen) {
    lens = chosen;
    again();
  }

  load();

  const oldest = $derived(people.at(-1)?.uuid ?? null);

  async function open() {
    nickname = "";
    email = "";
    password = "";
    scopes = [...STANDARD];
    created = null;
    adding = true;
    feedback.clear();

    if (supported.length) return;

    const data = await feedback.attempt(() =>
      api.query("query Scopes { scopesSupported minimumPassword }"),
    );

    if (data) {
      supported = data.scopesSupported;
      minimum = data.minimumPassword;
    }
  }

  function close() {
    adding = false;
    feedback.clear();
  }

  async function send() {
    busy = true;

    const data = await feedback.attempt(() =>
      api.query(CREATE, {
        nickname: nickname.trim() || null,
        email: email.trim() || null,
        password: password || null,
        scopes,
      }),
    );

    busy = false;

    if (!data) return;

    created = data.createActor;
    adding = false;

    await load();
  }

  const blocked = (actor) => actor.devices.some((device) => device.blockedAt);

  const presence = (actor) => {
    const parts = [
      `${actor.sessions.length} session${actor.sessions.length === 1 ? "" : "s"}`,
      `${actor.devices.length} device${actor.devices.length === 1 ? "" : "s"}`,
    ];

    return parts.join(" · ");
  };

  const DEVICE_LENSES = [
    ["allowed", "Allowed", { blocked: false }],
    ["blocked", "Blocked", { blocked: true }],
    ["unattached", "Never signed in", { unattached: true }],
  ];

  const DEVICES_QUERY = `
    query Devices($blocked: Boolean, $unattached: Boolean, $agent: String, $limit: Int) {
      devices(blocked: $blocked, unattached: $unattached, agent: $agent, limit: $limit) {
        id label category known ipAddress userAgent lastSeenAt blockedAt
        actors { uuid identifier }
        sessions { id }
      }
    }
  `;

  const DEVICE_LIMIT = 100;

  const DEVICE_COLUMNS = [
    "",
    "Device",
    { label: "Who signs in on it", hide: true },
    { label: "IP address", hide: true },
    "Last seen",
  ];

  let devices = $state([]);
  let devicesLoading = $state(true);
  let deviceLens = $state("allowed");
  let deviceSearch = $state("");
  let agent = $state("");
  let chosenDevices = $state(new Set());
  let refuse = $state(false);
  let deviceBusy = $state(false);

  const deviceNarrowing = $derived(DEVICE_LENSES.find(([key]) => key === deviceLens)?.[2] ?? {});

  async function loadDevices() {
    devicesLoading = true;

    const data = await feedback.attempt(() =>
      api.query(DEVICES_QUERY, {
        blocked: deviceNarrowing.blocked ?? null,
        unattached: deviceNarrowing.unattached ?? null,
        agent: agent || null,
        limit: DEVICE_LIMIT,
      }),
    );

    devicesLoading = false;

    if (data) {
      devices = data.devices;
      chosenDevices = new Set();
    }
  }

  loadDevices();

  function lookDevices(key) {
    deviceLens = key;
    loadDevices();
  }

  function filterDevices() {
    agent = deviceSearch.trim();
    refuse = false;
    loadDevices();
  }

  function clearDeviceFilter() {
    deviceSearch = "";
    filterDevices();
  }

  function toggleDevice(id) {
    const next = new Set(chosenDevices);

    next.has(id) ? next.delete(id) : next.add(id);
    chosenDevices = next;
  }

  const allDevicesChosen = $derived(devices.length > 0 && chosenDevices.size === devices.length);

  function toggleAllDevices() {
    chosenDevices = allDevicesChosen ? new Set() : new Set(devices.map((device) => device.id));
  }

  const blockingDevices = $derived(deviceLens !== "blocked");
  const devicePlural = (count) => `${count} device${count === 1 ? "" : "s"}`;

  function deviceOutcome(count, spared) {
    const done = `${blockingDevices ? "Blocked" : "Unblocked"} ${devicePlural(count)}.`;

    return spared ? `${done} The device you are using was left alone.` : done;
  }

  async function bulkDevices(variables, question) {
    if (!confirm(question)) return;

    deviceBusy = true;

    const mutation = blockingDevices
      ? `mutation Bulk($ids: [ID!], $agent: String, $refuse: Boolean) {
          blockDevices(ids: $ids, agent: $agent, refuse: $refuse) { count spared }
        }`
      : `mutation Bulk($ids: [ID!]!) { unblockDevices(ids: $ids) { count } }`;

    const data = await feedback.attempt(() => api.query(mutation, variables));

    deviceBusy = false;

    if (!data) return;

    const answer = data.blockDevices ?? data.unblockDevices;

    await loadDevices();
    feedback.say(
      refuse && variables.agent
        ? `${deviceOutcome(answer.count, answer.spared)} "${variables.agent}" is refused from now on.`
        : deviceOutcome(answer.count, answer.spared),
    );
  }

  const blockChosenDevices = () =>
    bulkDevices(
      { ids: [...chosenDevices] },
      blockingDevices
        ? `Block ${devicePlural(chosenDevices.size)}? Each is signed out and refused before any password is checked.`
        : `Unblock ${devicePlural(chosenDevices.size)}?`,
    );

  const blockMatchingDevices = () =>
    bulkDevices(
      { agent, refuse },
      `Block every device whose user agent contains "${agent}", including any not listed here?${
        refuse ? ` New devices sending it are refused too.` : ""
      }`,
    );

  const noDevices = $derived(
    deviceLens === "blocked"
      ? "Nothing is blocked."
      : deviceLens === "unattached"
        ? "Every device here has signed somebody in."
        : "No device has reached this server yet.",
  );
</script>

<Page title="People">
  {#snippet actions()}
    <div class="range" role="group" aria-label="Who to show">
      {#each LENSES as [key, label] (key)}
        <button type="button" aria-pressed={lens === key} onclick={() => look(key)}>{label}</button>
      {/each}
    </div>

    <Search
      bind:value={search}
      label="Search people"
      placeholder="nickname, email or name"
      onsearch={again}
    />
    <button type="button" class="btn btn-primary btn-sm" onclick={open}>Add person</button>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if adding}
    <Card title="Add person">
      <div class="grid gap-3 sm:grid-cols-2">
        <Field
          label="Nickname"
          bind:value={nickname}
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          placeholder="ada"
        />
        <Field label="Email" type="email" bind:value={email} placeholder="ada@example.com" />
      </div>

      <Field
        label="Password"
        type="password"
        bind:value={password}
        autocomplete="new-password"
        placeholder="blank sends a one-time link"
      />

      {#if password}
        <p class="text-xs opacity-60">At least {minimum} characters, and you will know it.</p>
      {/if}

      <div class="flex flex-col gap-2">
        <span class="legend">Scopes</span>
        <ScopesEditor
          value={scopes}
          available={supported}
          onchange={(chosen) => (scopes = chosen)}
        />
      </div>

      <div class="flex gap-2">
        <button
          type="button"
          class="btn btn-primary btn-sm"
          disabled={busy || !(nickname.trim() || email.trim())}
          onclick={send}
        >
          {busy ? "Adding..." : password ? "Create the account" : "Send the invitation"}
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onclick={close}>Cancel</button>
      </div>
    </Card>
  {/if}

  {#if created}
    <Card title={created.actor.activated ? "Account created" : "Invitation sent"}>
      <p class="text-sm opacity-70">
        {#if created.actor.activated}
          {created.actor.identifier} can sign in now.{created.url
            ? " This link confirms their address:"
            : ""}
        {:else if created.delivered}
          Emailed — accepting it proves the address.
        {:else}
          Pass this link along yourself. It works once.
        {/if}
      </p>

      {#if created.url}
        <p class="rounded bg-base-200 px-2 py-1 font-mono text-xs break-all">{created.url}</p>
      {/if}
    </Card>
  {/if}

  {#if loading && people.length === 0}
    <Spinner />
  {:else}
    <Table
      columns={COLUMNS}
      count={people.length}
      empty={search.trim()
        ? `No person matches "${search.trim()}".`
        : lens === "waiting"
          ? "Nobody is awaiting approval."
          : lens === "invited"
          ? "Nobody is waiting on an invitation."
          : lens === "managers"
            ? "Nobody else holds masks:manage."
            : lens === "suspended"
            ? "Nobody is suspended."
            : "Nobody can sign in yet. Add the first person."}
    >
      {#snippet rows()}
        {#each people as actor (actor.uuid)}
          <Row to={`/people/${actor.uuid}`}>
            <td>
              <div class="flex items-center gap-3">
                <img
                  src={`${actor.avatars.photo ?? actor.avatars.identicon}?size=32`}
                  width="32"
                  height="32"
                  alt=""
                  class="size-8 shrink-0 rounded object-cover"
                  class:drawn={!actor.avatars.photo}
                />
                <div class="min-w-0">
                  <Link to={`/people/${actor.uuid}`} class="link link-hover font-medium">
                    {actor.identifier}
                  </Link>
                  <div class="flex items-center gap-1.5 text-xs opacity-50">
                    <span class="truncate">
                      {actor.name ? `${actor.name} · ` : ""}{actor.email ?? "no email"}
                    </span>
                    {#if actor.email && !actor.emailVerified}
                      <span class="badge badge-warning badge-xs shrink-0">unconfirmed</span>
                    {/if}
                  </div>

                  <div class="mt-1 flex flex-wrap items-center gap-1 text-xs opacity-70 md:hidden">
                    {#if !actor.activated}
                      <span class="badge badge-info badge-xs">invited</span>
                    {:else}
                      <span>Last seen {day(actor.lastLoginAt, "never")}</span>
                    {/if}
                  </div>

                  {#if actor.otpEnabled || blocked(actor)}
                    <div class="mt-1 flex flex-wrap gap-1 md:hidden">
                      {#if actor.otpEnabled}
                        <span class="badge badge-success badge-xs">authenticator</span>
                      {/if}
                      {#if blocked(actor)}
                        <span class="badge badge-error badge-xs">blocked</span>
                      {/if}
                    </div>
                  {/if}
                </div>
              </div>
            </td>

            <td class="hidden text-xs md:table-cell">
              <div class="max-w-64 truncate font-mono" title={joined(actor.scopes)}>
                {#each actor.scopes as scope (scope)}<span
                    class="scope"
                    class:scope-privileged={scope.startsWith("masks:")}>{scope}</span
                  >{" "}{/each}
              </div>
            </td>

            <td class="hidden md:table-cell">
              {#if actor.otpEnabled}
                <span class="badge badge-success badge-sm">authenticator</span>
                <div class="mt-1 text-xs whitespace-nowrap opacity-60">
                  {actor.backupCodesRemaining} backup codes
                </div>
              {:else}
                <span class="badge badge-ghost badge-sm">password</span>
              {/if}
            </td>

            <td class="hidden text-xs whitespace-nowrap opacity-70 md:table-cell">
              {presence(actor)}
              {#if blocked(actor)}
                <span class="badge badge-error badge-xs ml-1">blocked</span>
              {/if}
            </td>

            <td class="hidden text-xs whitespace-nowrap opacity-70 md:table-cell">
              {#if !actor.activated}
                <span class="badge badge-info badge-sm">invited</span>
              {:else}
                {day(actor.lastLoginAt, "never")}
              {/if}
            </td>
          </Row>
        {/each}
      {/snippet}
    </Table>

    {#if !exhausted && people.length}
      <div>
        <button
          type="button"
          class="btn btn-ghost btn-sm"
          disabled={more}
          onclick={() => load(oldest)}
        >
          {more ? "Loading..." : "Show more"}
        </button>
      </div>
    {/if}
  {/if}

  <Card title="Devices">
    {#snippet actions()}
      <Search
        bind:value={deviceSearch}
        label="Filter by user agent"
        placeholder="curl, python-requests"
        onsearch={filterDevices}
      />
      <div class="range" role="group" aria-label="Which devices">
        {#each DEVICE_LENSES as [key, label] (key)}
          <button type="button" aria-pressed={deviceLens === key} onclick={() => lookDevices(key)}
            >{label}</button
          >
        {/each}
      </div>
    {/snippet}

    {#if agent && blockingDevices}
      <div class="alert alert-warning alert-soft flex-col items-start gap-2">
        <p class="text-sm">
          Showing devices whose user agent contains <code class="font-mono">{agent}</code>.
          <button type="button" class="link" onclick={clearDeviceFilter}>Clear</button>
        </p>
        <label class="flex items-center gap-2 text-sm">
          <input type="checkbox" class="checkbox" bind:checked={refuse} />
          Also refuse this user agent from now on
        </label>
        <button
          type="button"
          class="btn btn-sm btn-error btn-outline"
          disabled={deviceBusy}
          onclick={blockMatchingDevices}
        >
          Block every matching device
        </button>
      </div>
    {:else if agent}
      <p class="text-sm opacity-70">
        Showing blocked devices whose user agent contains <code class="font-mono">{agent}</code>.
        <button type="button" class="link" onclick={clearDeviceFilter}>Clear</button>
      </p>
    {/if}

    {#if devices.length}
      <div class="flex flex-wrap items-center gap-3">
        <label class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            class="checkbox"
            checked={allDevicesChosen}
            indeterminate={chosenDevices.size > 0 && !allDevicesChosen}
            onchange={toggleAllDevices}
          />
          {chosenDevices.size
            ? `${chosenDevices.size} chosen`
            : `Choose all ${devicePlural(devices.length)} shown`}
        </label>
        {#if chosenDevices.size}
          <button
            type="button"
            class="btn btn-sm {blockingDevices ? 'btn-error btn-outline' : 'btn-outline'}"
            disabled={deviceBusy}
            onclick={blockChosenDevices}
          >
            {blockingDevices ? "Block" : "Unblock"} {devicePlural(chosenDevices.size)}
          </button>
        {/if}
        {#if devices.length === DEVICE_LIMIT}
          <span class="text-xs opacity-60">Only the newest {DEVICE_LIMIT} are shown.</span>
        {/if}
      </div>
    {/if}

    {#if devicesLoading && devices.length === 0}
      <Spinner />
    {:else}
      <Table columns={DEVICE_COLUMNS} count={devices.length} empty={noDevices}>
        {#snippet rows()}
          {#each devices as device (device.id)}
            <Row to={`/devices/${device.id}`}>
              <td class="w-0">
                <input
                  type="checkbox"
                  class="checkbox"
                  aria-label={`Choose ${device.label}`}
                  checked={chosenDevices.has(device.id)}
                  onchange={() => toggleDevice(device.id)}
                />
              </td>
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
  </Card>
</Page>
