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

  const CREATE = `
    mutation Create($nickname: String!, $email: String, $password: String, $scopes: [String!]) {
      createActor(nickname: $nickname, email: $email, password: $password, scopes: $scopes) {
        delivered url actor { uuid nickname activated }
      }
    }
  `;

  const STANDARD = ["openid", "profile", "email", "offline_access"];

  const COLUMNS = [
    "Person",
    { label: "Scopes", hide: true },
    { label: "Second factor", hide: true },
    { label: "Signed in on", hide: true },
    "Last seen",
  ];

  const feedback = createFeedback();

  let search = $state("");
  let people = $state([]);
  let loose = $state([]);
  let loading = $state(true);

  let adding = $state(false);
  let nickname = $state("");
  let email = $state("");
  let password = $state("");
  let scopes = $state([...STANDARD]);
  let supported = $state([]);
  let minimum = $state(8);
  let busy = $state(false);
  let created = $state(null);

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
        nickname,
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

  const blocked = (actor) => actor.devices.some((device) => device.blockedAt);

  const presence = (actor) => {
    const parts = [
      `${actor.sessions.length} session${actor.sessions.length === 1 ? "" : "s"}`,
      `${actor.devices.length} device${actor.devices.length === 1 ? "" : "s"}`,
    ];

    return parts.join(" · ");
  };
</script>

<Page title="People">
  {#snippet actions()}
    <Search
      bind:value={search}
      label="Search people"
      placeholder="nickname, email or name"
      onsearch={load}
    />
    <button type="button" class="btn btn-primary btn-sm" onclick={open}>Add somebody</button>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if adding}
    <Card title="Add somebody">
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
          disabled={busy || !nickname.trim()}
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
          {created.actor.nickname} can sign in now.{created.url
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
        ? `No person matches “${search.trim()}”.`
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
                    {actor.nickname}
                  </Link>
                  <div class="flex items-center gap-1.5 text-xs opacity-50">
                    <span class="truncate">
                      {actor.name ? `${actor.name} · ` : ""}{actor.email ?? "no email"}
                    </span>
                    {#if actor.email && !actor.emailVerified}
                      <span class="badge badge-warning badge-xs shrink-0">unconfirmed</span>
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

            <td class="text-xs whitespace-nowrap opacity-70">
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

    {#if loose.length}
      <Card title="Devices nobody has signed in on">
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
