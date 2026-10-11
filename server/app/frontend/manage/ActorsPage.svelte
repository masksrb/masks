<script>
  import Marks from "./ui/Marks.svelte";
  import { t } from "./lib/copy.js";
  import { createPages } from "./lib/pages.svelte.js";
  import Pager from "./ui/Pager.svelte";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import Devices from "./Devices.svelte";
  import ScopesEditor from "./ScopesEditor.svelte";
  import Section from "./ui/Section.svelte";
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
    sessions { id }
    devices { id blockedAt }
  `;

  const pages = createPages();

  const LENSES = [
    ["everyone", t("actors.lenses.everyone"), {}],
    ["invited", t("actors.lenses.invited"), { activated: false }],
    ["waiting", t("actors.lenses.waiting"), { pendingApproval: true }],
    ["help", t("actors.lenses.help"), { recoveryRequested: true }],
    ["managers", t("actors.lenses.managers"), { holds: "masks:manage" }],
    ["suspended", t("actors.lenses.suspended"), { suspended: true }],
  ];

  const QUERY = `
    query Actors(
      $search: String, $activated: Boolean, $holds: String, $pendingApproval: Boolean,
      $recoveryRequested: Boolean, $suspended: Boolean, $afterId: ID, $limit: Int
    ) {
      actors(
        search: $search, activated: $activated, holds: $holds, pendingApproval: $pendingApproval,
        recoveryRequested: $recoveryRequested, suspended: $suspended, afterId: $afterId, limit: $limit
      ) {
        uuid identifier nickname name email emailVerified otpEnabled backupCodesRemaining
        lastLoginAt scopes activated invitedAt pendingApproval recoveryRequestedAt suspendedAt
        avatars { photo identicon }
        ${PRESENCE}
      }
      actorCount(
        search: $search, activated: $activated, holds: $holds, pendingApproval: $pendingApproval,
        recoveryRequested: $recoveryRequested, suspended: $suspended
      )
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
    t("actors.columns.actor"),
    { label: t("actors.columns.signed_in_on"), hide: true },
    { label: t("actors.columns.last_seen"), hide: true },
  ];

  const feedback = createFeedback();

  let search = $state("");
  let actors = $state([]);
  let loading = $state(true);
  let lens = $state("everyone");

  const narrowing = $derived(LENSES.find(([key]) => key === lens)?.[2] ?? {});

  let adding = $state(false);
  let inviting = $state(false);
  let addresses = $state("");
  let joining = $state([]);
  let groups = $state([]);
  let invited = $state(null);

  let groupsLoaded = false;

  const invitedCount = $derived(invited?.filter((one) => one.outcome === "invited").length ?? 0);

  async function openInvites() {
    inviting = true;
    invited = null;

    if (groupsLoaded) return;

    const data = await feedback.attempt(() => api.query("query Groups { groups { key name } }"));

    if (!data) return;

    groups = data.groups;
    groupsLoaded = true;
  }

  async function inviteMany() {
    busy = true;

    const data = await feedback.attempt(() =>
      api.query(
        `mutation Invite($emails: [String!]!, $groups: [String!]) {
          inviteActors(emails: $emails, groups: $groups) { outcomes { email outcome url } }
        }`,
        { emails: addresses.split(/[\s,;]+/).filter(Boolean), groups: joining },
      ),
    );

    busy = false;

    if (!data) return;

    invited = data.inviteActors.outcomes;
    inviting = false;
    addresses = "";
    again();
  }
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
      const data = await api.query(QUERY, {
        search: search.trim() || null,
        activated: narrowing.activated ?? null,
        holds: narrowing.holds ?? null,
        pendingApproval: narrowing.pendingApproval ?? null,
        recoveryRequested: narrowing.recoveryRequested ?? null,
        suspended: narrowing.suspended ?? null,
        afterId: pages.cursor,
        limit: pages.size,
      });

      actors = data.actors;
      pages.counted(data.actorCount);
    } catch (thrown) {
      feedback.blame(thrown);
    } finally {
      loading = false;
    }
  }

  function again() {
    pages.reset();
    load();
  }

  function turn(direction) {
    if (direction === "forward") pages.forward(actors.at(-1)?.uuid);
    else pages.back();

    load();
  }

  function look(chosen) {
    lens = chosen;
    again();
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

    pages.reset();
    await load();
  }

  const blocked = (actor) => actor.devices.some((device) => device.blockedAt);

  const marks = (actor) =>
    [
      actor.scopes.some((scope) => scope.startsWith("masks:")) && ["manager", t("actors.marks.manager"), "primary"],
      actor.otpEnabled && ["key", t("actors.marks.second_factor", { count: actor.backupCodesRemaining }), "good"],
      !actor.activated && ["invited", t("actors.marks.invited"), "info"],
      actor.email && !actor.emailVerified && ["unconfirmed", t("actors.marks.unconfirmed"), "warn"],
      actor.pendingApproval && ["waiting", t("actors.marks.waiting"), "warn"],
      actor.recoveryRequestedAt && ["help", t("actors.marks.help"), "warn"],
      actor.suspendedAt && ["suspended", t("actors.marks.suspended"), "bad"],
      blocked(actor) && ["blocked", t("actors.marks.blocked"), "bad"],
    ].filter(Boolean);

  const presence = (actor) => {
    const parts = [
      t("actors.sessions", { count: actor.sessions.length }),
      t("actors.devices", { count: actor.devices.length }),
    ];

    return parts.join(" · ");
  };
</script>

<Page title={t("actors.title")}>
  {#snippet actions()}
    <div class="range" role="group" aria-label={t("actors.who")}>
      {#each LENSES as [key, label] (key)}
        <button type="button" aria-pressed={lens === key} onclick={() => look(key)}>{label}</button>
      {/each}
    </div>

    <Search
      bind:value={search}
      label={t("actors.search")}
      placeholder={t("actors.search_placeholder")}
      onsearch={again}
    />
    <button type="button" class="btn btn-sm" onclick={openInvites}>{t("actors.invite_many")}</button>
    <button type="button" class="btn btn-primary btn-sm" onclick={open}>{t("actors.add")}</button>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if inviting}
    <Section title={t("actors.invites.title")} lede={t("actors.invites.lede")}>
      <label class="flex flex-col gap-1.5">
        <span class="field-label">{t("actors.invites.addresses")}</span>
        <textarea class="textarea w-full font-mono text-sm" rows="6" bind:value={addresses}></textarea>
      </label>

      {#if groups.length}
        <fieldset class="flex flex-col gap-1">
          <legend class="field-label">{t("actors.invites.groups")}</legend>
          {#each groups as group (group.key)}
            <label class="flex items-center gap-2 text-sm">
              <input type="checkbox" class="checkbox checkbox-sm" value={group.key} bind:group={joining} />
              {group.name}
            </label>
          {/each}
        </fieldset>
      {/if}

      <div class="flex flex-wrap gap-2">
        <button type="button" class="btn btn-primary btn-sm" disabled={busy || !addresses.trim()} onclick={inviteMany}>
          {busy ? t("actors.form.adding") : t("actors.invites.send")}
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onclick={() => (inviting = false)}>{t("actors.form.cancel")}</button>
      </div>
    </Section>
  {/if}

  {#if invited}
    <Section title={t("actors.invites.done", { count: invitedCount })}>
      <ul class="flex flex-col gap-1 text-sm">
        {#each invited as one (one.email)}
          <li class="flex flex-wrap items-baseline gap-x-2">
            <span class="font-mono">{one.email}</span>
            <span class="opacity-80">{t(`actors.invites.outcomes.${one.outcome}`)}</span>
            {#if one.url}<code class="tray px-1 text-xs break-all">{one.url}</code>{/if}
          </li>
        {/each}
      </ul>
    </Section>
  {/if}

  {#if adding}
    <Section title={t("actors.add")}>
      <div class="grid gap-3 sm:grid-cols-2">
        <Field
          label={t("actors.form.nickname")}
          bind:value={nickname}
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          placeholder="ada"
        />
        <Field label={t("actors.form.email")} type="email" bind:value={email} placeholder="ada@example.com" />
      </div>

      <Field
        label={t("actors.form.password")}
        type="password"
        bind:value={password}
        autocomplete="new-password"
        placeholder={t("actors.form.password_placeholder")}
      />

      {#if password}
        <p class="hint">{t("actors.form.minimum", { count: minimum })}</p>
      {/if}

      <div class="flex flex-col gap-2">
        <span class="legend">{t("actors.form.scopes")}</span>
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
          {busy
            ? t("actors.form.adding")
            : password
              ? t("actors.form.create")
              : t("actors.form.invite")}
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onclick={close}>{t("actors.form.cancel")}</button>
      </div>
    </Section>
  {/if}

  {#if created}
    <Section title={created.actor.activated ? t("actors.created.account") : t("actors.created.invitation")}>
      <p class="text-sm opacity-85">
        {#if created.actor.activated}
          {t("actors.created.can_sign_in", { identifier: created.actor.identifier })}{created.url
            ? ` ${t("actors.created.confirm_link")}`
            : ""}
        {:else if created.delivered}
          {t("actors.created.emailed")}
        {:else}
          {t("actors.created.pass_along")}
        {/if}
      </p>

      {#if created.url}
        <p class="tray px-2 py-1 font-mono text-xs break-all">{created.url}</p>
      {/if}
    </Section>
  {/if}

  {#if loading && actors.length === 0}
    <Spinner />
  {:else}
    <Table
      columns={COLUMNS}
      count={actors.length}
      empty={search.trim()
        ? t("actors.empty.search", { search: search.trim() })
        : t(`actors.empty.${lens}`)}
    >
      {#snippet rows()}
        {#each actors as actor (actor.uuid)}
          <Row to={`/actors/${actor.uuid}`}>
            <td class="w-full max-w-0 md:w-auto md:max-w-none">
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
                  <div class="flex min-w-0 items-center gap-2">
                    <Link to={`/actors/${actor.uuid}`} class="link link-hover truncate font-medium">
                      {actor.identifier}
                    </Link>
                    <Marks marks={marks(actor)} />
                  </div>
                  <div class="hint truncate text-xs">
                    {actor.name ? `${actor.name} · ` : ""}{actor.email ?? t("actors.no_email")}<span class="md:hidden">
                      {" · "}{actor.activated ? day(actor.lastLoginAt, t("actors.never")) : t("actors.never")}</span
                    >
                  </div>
                </div>
              </div>
            </td>

            <td class="hidden text-xs whitespace-nowrap opacity-85 md:table-cell">{presence(actor)}</td>

            <td class="hidden text-xs whitespace-nowrap opacity-85 md:table-cell">
              {actor.activated ? day(actor.lastLoginAt, t("actors.never")) : t("actors.never")}
            </td>
          </Row>
        {/each}
      {/snippet}
    </Table>

    <Pager {pages} shown={actors.length} busy={loading} onpage={turn} />
  {/if}

  <Devices {api} {feedback} />
</Page>
