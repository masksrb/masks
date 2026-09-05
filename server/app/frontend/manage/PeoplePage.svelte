<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, moment, since } from "./lib/format.js";
  import Presence from "./Presence.svelte";
  import ScopesEditor from "./ScopesEditor.svelte";
  import Card from "./ui/Card.svelte";
  import Field from "./ui/Field.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Search from "./ui/Search.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Table from "./ui/Table.svelte";

  let { api } = $props();

  const PRESENCE = `
    sessions { id ipAddress userAgent authenticatedAt expiresAt }
    devices { id label category known ipAddress userAgent lastSeenAt blockedAt }
  `;

  const QUERY = `
    query People($search: String) {
      actors(search: $search) {
        uuid nickname name email emailVerified otpEnabled backupCodesRemaining
        lastLoginAt scopes activated invitedAt
        avatars { photo identicon }
        ${PRESENCE}
      }
      devices(unattached: true) {
        id label category known ipAddress userAgent lastSeenAt blockedAt
      }
    }
  `;

  const INVITE = `
    mutation Invite($nickname: String!, $email: String!, $scopes: [String!]) {
      inviteActor(nickname: $nickname, email: $email, scopes: $scopes) {
        delivered url actor { uuid }
      }
    }
  `;

  const STANDARD = ["openid", "profile", "email", "offline_access"];

  const COLUMNS = [
    { label: "" },
    "Person",
    "Scopes",
    "Second factor",
    "Signed in on",
    "Last seen",
  ];

  const feedback = createFeedback();

  let search = $state("");
  let people = $state([]);
  let loose = $state([]);
  let loading = $state(true);
  let opened = $state(new Set());

  let inviting = $state(false);
  let nickname = $state("");
  let email = $state("");
  let scopes = $state([...STANDARD]);
  let supported = $state([]);
  let busy = $state(false);
  let invited = $state(null);

  async function load() {
    loading = true;

    try {
      const data = await api.query(QUERY, { search: search.trim() || null });

      people = data.actors;
      loose = data.devices;
    } catch (thrown) {
      feedback.blame(thrown);
    } finally {
      loading = false;
    }
  }

  load();

  function toggle(actor) {
    const held = new Set(opened);

    held.has(actor.uuid) ? held.delete(actor.uuid) : held.add(actor.uuid);
    opened = held;
  }

  async function open() {
    nickname = "";
    email = "";
    scopes = [...STANDARD];
    invited = null;
    inviting = true;
    feedback.clear();

    if (supported.length) return;

    const data = await feedback.attempt(() => api.query("query Scopes { scopesSupported }"));

    if (data) supported = data.scopesSupported;
  }

  function close() {
    inviting = false;
    feedback.clear();
  }

  async function send() {
    busy = true;

    const data = await feedback.attempt(() => api.query(INVITE, { nickname, email, scopes }));

    busy = false;

    if (!data) return;

    invited = data.inviteActor;
    inviting = false;

    await load();
  }

  async function onDevice(mutation, device, notice, question = null) {
    if (question && !confirm(question)) return;

    const done = await feedback.attempt(
      () =>
        api.query(`mutation Act($id: ID!) { ${mutation}(id: $id) { device { id } } }`, {
          id: device.id,
        }),
      notice,
    );

    if (done) await load();
  }

  const block = (device) =>
    onDevice(
      "blockDevice",
      device,
      `${device.label} is blocked.`,
      `Block ${device.label}? It is refused before any password is checked.`,
    );

  const unblock = (device) => onDevice("unblockDevice", device, `${device.label} is unblocked.`);

  const presence = (actor) => {
    const parts = [
      `${actor.sessions.length} session${actor.sessions.length === 1 ? "" : "s"}`,
      `${actor.devices.length} device${actor.devices.length === 1 ? "" : "s"}`,
    ];

    return parts.join(" · ");
  };
</script>

<Page
  title="People"
  lede="Everyone who can sign in through this server: what each of them may be granted, and where they are signed in right now."
>
  {#snippet actions()}
    <Search
      bind:value={search}
      label="Search people"
      placeholder="nickname, email or name"
      onsearch={load}
    />
    <button type="button" class="btn btn-primary btn-sm" onclick={open}>Invite somebody</button>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if inviting}
    <Card
      title="Invite somebody"
      lede="They choose their own password from a one-time link. Nothing is granted until they accept."
    >
      <div class="grid gap-3 sm:grid-cols-2">
        <Field
          label="Username"
          bind:value={nickname}
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          placeholder="ada"
        />
        <Field label="Email" type="email" bind:value={email} placeholder="ada@example.com" />
      </div>

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
          disabled={busy || !nickname.trim() || !email.trim()}
          onclick={send}
        >
          {busy ? "Sending..." : "Send the invitation"}
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onclick={close}>Cancel</button>
      </div>
    </Card>
  {/if}

  {#if invited}
    <Card title="Invitation sent">
      {#if invited.delivered}
        <p class="max-w-prose text-sm opacity-70">
          The link was emailed. It is not shown here, so that accepting it proves the address.
        </p>
      {:else}
        <p class="max-w-prose text-sm opacity-70">
          No mailer is configured, so pass this link along yourself. It works once.
        </p>
        <p class="rounded bg-base-200 px-2 py-1 font-mono text-xs break-all">{invited.url}</p>
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
        ? `No person matches “${search.trim()}”.`
        : "Nobody can sign in yet. Invite the first person."}
    >
      {#snippet rows()}
        {#each people as actor (actor.uuid)}
          {@const showing = opened.has(actor.uuid)}
          <tr class="hover">
            <td class="w-8 align-top">
              <button
                type="button"
                class="caret"
                aria-expanded={showing}
                aria-label={showing ? `Hide ${actor.nickname}` : `Show ${actor.nickname}`}
                onclick={() => toggle(actor)}
              >
                {showing ? "−" : "+"}
              </button>
            </td>

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
                    {actor.nickname}
                  </Link>
                  <div class="text-xs opacity-50">
                    {actor.name ? `${actor.name} · ` : ""}{actor.email ?? "no email"}
                    {#if actor.email && !actor.emailVerified}
                      <span class="badge badge-warning badge-xs ml-1">unconfirmed</span>
                    {/if}
                  </div>
                </div>
              </div>
            </td>

            <td class="text-xs">
              <div class="flex max-w-64 flex-wrap gap-x-2 font-mono">
                {#each actor.scopes as scope (scope)}
                  <span class="scope" class:scope-privileged={scope.startsWith("masks:")}
                    >{scope}</span
                  >
                {/each}
              </div>
            </td>

            <td>
              {#if actor.otpEnabled}
                <span class="badge badge-success badge-sm">authenticator</span>
                <div class="mt-1 text-xs whitespace-nowrap opacity-60">
                  {actor.backupCodesRemaining} backup codes
                </div>
              {:else}
                <span class="badge badge-ghost badge-sm">password only</span>
              {/if}
            </td>

            <td class="text-xs whitespace-nowrap opacity-70">
              {presence(actor)}
              {#if actor.devices.some((device) => device.blockedAt)}
                <span class="badge badge-error badge-xs ml-1">blocked</span>
              {/if}
            </td>

            <td class="text-xs whitespace-nowrap opacity-70">
              {#if !actor.activated}
                <span class="badge badge-info badge-sm">invited</span>
              {:else}
                {day(actor.lastLoginAt, "never")}
              {/if}
            </td>
          </tr>

          {#if showing}
            <tr class="bare">
              <td colspan={COLUMNS.length} class="p-0">
                <div class="drawer-panel">
                  <Presence {api} {feedback} {actor} onchange={load} columns />

                  <Link to={`/people/${actor.uuid}`} class="link text-xs">
                    Everything about {actor.nickname} &rarr;
                  </Link>
                </div>
              </td>
            </tr>
          {/if}
        {/each}
      {/snippet}
    </Table>

    {#if loose.length}
      <Card
        title="Devices nobody has signed in on"
        lede="Browsers this server has recognised that never carried a session. Blocking one refuses it before any password is checked."
      >
        <ul class="flex flex-col gap-1.5">
          {#each loose as device (device.id)}
            <li class="slat">
              <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                <span class="flex flex-wrap items-baseline gap-2">
                  <span class="text-sm font-medium">{device.label}</span>
                  {#if device.blockedAt}
                    <span class="badge badge-error badge-xs">blocked</span>
                  {:else if !device.known}
                    <span class="badge badge-warning badge-xs">unrecognised</span>
                  {/if}
                </span>

                {#if device.blockedAt}
                  <button type="button" class="link text-xs" onclick={() => unblock(device)}>
                    Unblock
                  </button>
                {:else}
                  <button
                    type="button"
                    class="link text-xs text-error"
                    onclick={() => block(device)}
                  >
                    Block
                  </button>
                {/if}
              </div>

              <span class="truncate text-xs opacity-45">{device.userAgent ?? device.category}</span>

              <div class="flex flex-wrap gap-x-4 text-xs opacity-60">
                <span class="font-mono">{device.ipAddress ?? "—"}</span>
                <span title={moment(device.lastSeenAt)}>Last seen {since(device.lastSeenAt)}</span>
              </div>
            </li>
          {/each}
        </ul>
      </Card>
    {/if}
  {/if}
</Page>
