<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { t } from "./lib/copy.js";
  import { day } from "./lib/format.js";
  import Events from "./Events.svelte";
  import DomainsSection from "./DomainsSection.svelte";
  import GroupsSection from "./GroupsSection.svelte";
  import Namespaces from "./Namespaces.svelte";
  import ScopesEditor from "./ScopesEditor.svelte";
  import BarChart from "./ui/BarChart.svelte";
  import Section from "./ui/Section.svelte";
  import Select from "./ui/Select.svelte";
  import Facts from "./ui/Facts.svelte";
  import Field from "./ui/Field.svelte";
  import Link from "./ui/Link.svelte";
  import OrganizationCell from "./OrganizationCell.svelte";
  import OrganizationHeadcount from "./OrganizationHeadcount.svelte";
  import Loader from "./ui/Loader.svelte";
  import Notices from "./ui/Notices.svelte";
  import Switch from "./ui/Switch.svelte";
  import Tally from "./ui/Tally.svelte";
  import Page from "./ui/Page.svelte";
  import Row from "./ui/Row.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Table from "./ui/Table.svelte";

  let { api, boot, overview = false } = $props();

  const QUERY = `
    query Tenant {
      tenant {
        uuid subdomain name namedBy dynamicRegistration dynamicClientScopes createdAt mails accentColor logoUrl keyRotationDays
        browsersOnly blockedAgents suspendAfter deleteAfter eventRetentionDays riskyNetworks
        signInPolicy { key name }
        signingKeys { kid algorithm activatedAt retiredAt state }
      }
      viewer { identifier scopes }
      tally { actors clients devices organizations }
      namespaces {
        name resource claimedAt releasable
        client { clientId name }
      }
      scopesSupported
      signInPolicies { key name }
    }
  `;

  const EVENT_FIELDS = `
    id action label createdAt ipAddress details
    actor { uuid identifier }
    by { uuid identifier }
    client { clientId name }
    device { id label }
  `;

  const ACTIVITY = `
    query Activity($days: Int) {
      activity(days: $days) { date signIns }
    }
  `;

  const RECENT = `
    query Recent {
      worrying: events(grave: true, limit: 8) { ${EVENT_FIELDS} }
      latest: events(limit: 8) { ${EVENT_FIELDS} }
    }
  `;

  const ORGANIZATIONS_SHOWN = 5;

  const ORGANIZATIONS = `
    query Organizations {
      organizations(limit: ${ORGANIZATIONS_SHOWN}) { key name memberCount ownerCount pendingCount }
    }
  `;

  const SPANS = [7, 30, 90];

  const RETENTION = [
    [30, t("settings.retention.days_30")],
    [90, t("settings.retention.days_90")],
    [180, t("settings.retention.days_180")],
    [365, t("settings.retention.a_year")],
    [1095, t("settings.retention.three_years")],
    [2555, t("settings.retention.seven_years")],
  ];

  const SUSPEND_AFTER = [
    [0, t("settings.idle.never")],
    [90, t("settings.idle.after_90_days")],
    [180, t("settings.idle.after_180_days")],
    [365, t("settings.idle.after_a_year")],
    [730, t("settings.idle.after_two_years")],
  ];

  const DELETE_AFTER = [
    [0, t("settings.idle.never")],
    [180, t("settings.idle.after_180_days")],
    [365, t("settings.idle.after_a_year")],
    [730, t("settings.idle.after_two_years")],
    [1095, t("settings.idle.after_three_years")],
  ];

  const choices = (listed, held) =>
    !held || listed.some(([days]) => days === held) ? listed : [...listed, [held, t("settings.after_days", { days: held })]];

  function deleteAfter(days) {
    if (days && !confirm(t("settings.idle.delete_confirm"))) return load();

    return update({ deleteAfter: days }, t("settings.idle.updated"));
  }

  const BADGE = {
    staged: "badge-warning",
    active: "badge-success",
    retiring: "badge-info",
    retired: "badge-ghost",
  };

  const MARK = new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short" });

  const feedback = createFeedback();

  let data = $state(null);
  let name = $state("");
  let agents = $state("");
  let networks = $state("");
  let loading = $state(true);
  let days = $state(30);

  const counts = $derived(
    data
      ? [
          { to: "/actors", label: t("settings.counts.actors"), value: data.tally.actors },
          { to: "/clients", label: t("settings.counts.clients"), value: data.tally.clients },
          { to: "/organizations", label: t("settings.counts.organizations"), value: data.tally.organizations },
          { to: "/actors#devices", label: t("settings.counts.devices"), value: data.tally.devices },
        ]
      : [],
  );

  const STARTED = "masks:manage:started";

  let hidden = $state(false);

  try {
    hidden = localStorage.getItem(STARTED) === "1";
  } catch {}

  function hideStarting() {
    hidden = true;

    try {
      localStorage.setItem(STARTED, "1");
    } catch {}
  }

  const starting = $derived(
    data
      ? [
          {
            done: data.tenant.mails,
            title: t("settings.starting.mail.title"),
            detail: t("settings.starting.mail.detail"),
            to: "/messages",
            action: t("settings.starting.mail.action"),
          },
          {
            done: data.tally.clients > 0,
            title: t("settings.starting.client.title"),
            detail: t("settings.starting.client.detail"),
            to: "/clients",
            action: t("settings.starting.client.action"),
          },
          {
            done: data.tally.actors > 1,
            title: t("settings.starting.invite.title"),
            detail: t("settings.starting.invite.detail"),
            to: "/actors",
            action: t("settings.starting.invite.action"),
          },
        ]
      : [],
  );

  const plotted = (rows) =>
    rows.map((row) => ({
      key: row.date,
      value: row.signIns,
      label: MARK.format(new Date(`${row.date}T00:00:00`)),
    }));

  async function load() {
    loading = true;

    try {
      data = await api.query(QUERY);
      name = data.tenant.name;
      agents = data.tenant.blockedAgents ?? "";
      networks = data.tenant.riskyNetworks ?? "";
    } catch (thrown) {
      feedback.blame(thrown);
    } finally {
      loading = false;
    }
  }

  load();

  async function update(changes, notice) {
    const done = await feedback.attempt(
      () =>
        api.query(
          `mutation Update(
            $name: String, $dynamicClientScopes: [String!], $dynamicRegistration: String,
            $namedBy: String, $browsersOnly: Boolean, $blockedAgents: String, $signInPolicy: ID, $riskyNetworks: String,
            $suspendAfter: Int, $deleteAfter: Int, $eventRetentionDays: Int, $accentColor: String, $keyRotationDays: Int
          ) {
            updateTenant(
              name: $name
              dynamicClientScopes: $dynamicClientScopes
              dynamicRegistration: $dynamicRegistration
              namedBy: $namedBy
              browsersOnly: $browsersOnly
              blockedAgents: $blockedAgents
              riskyNetworks: $riskyNetworks
              signInPolicy: $signInPolicy
              suspendAfter: $suspendAfter
              deleteAfter: $deleteAfter
              eventRetentionDays: $eventRetentionDays
              accentColor: $accentColor
              keyRotationDays: $keyRotationDays
            ) { tenant { name } }
          }`,
          changes,
        ),
      notice,
    );

    if (done) await load();
  }

  async function chooseLogo(event) {
    const input = event.currentTarget;
    const file = input.files?.[0];

    if (!file) return;

    await keys(
      `mutation Logo($logo: Upload!) { uploadTenantLogo(logo: $logo) { tenant { logoUrl } } }`,
      { logo: file },
      t("settings.branding.logo_updated"),
    );

    input.value = "";
  }

  async function keys(query, variables, notice) {
    const done = await feedback.attempt(() => api.query(query, variables), notice);

    if (done) await load();
  }

  const stage = () =>
    keys(
      `mutation Stage { stageSigningKey { signingKey { kid } } }`,
      {},
      t("settings.keys.staged_notice"),
    );

  function activate(kid) {
    if (!confirm(t("settings.keys.activate_confirm"))) return;

    return keys(
      `mutation Activate($kid: ID!) { activateSigningKey(kid: $kid) { signingKey { kid } } }`,
      { kid },
      t("settings.keys.activated_notice"),
    );
  }

  function discard(kid) {
    if (!confirm(t("settings.keys.discard_confirm"))) return;

    return keys(
      `mutation Discard($kid: ID!) { discardSigningKey(kid: $kid) { kid } }`,
      { kid },
      t("settings.keys.discarded"),
    );
  }

  function rotate() {
    if (!confirm(t("settings.keys.rotate_confirm"))) return;

    return keys(
      `mutation Rotate { rotateSigningKey { signingKey { kid } } }`,
      {},
      t("settings.keys.rotated"),
    );
  }
</script>

{#if loading && !data}
  <Spinner />
{:else if !data}
  <div class="alert alert-error alert-soft text-sm" role="alert">{feedback.state.failure}</div>
{:else if overview}
  <Page
    title={data.tenant.name}
    id={boot.issuer}
    hero
  >
    {#if !hidden && starting.some((step) => !step.done)}
      <Section title={t("settings.starting.title")}>
        {#snippet actions()}
          <button type="button" class="btn btn-ghost btn-sm" onclick={hideStarting}>{t("settings.starting.hide")}</button>
        {/snippet}

        <ol class="flex flex-col gap-3">
          {#each starting as step (step.title)}
            <li class="flex flex-wrap items-start justify-between gap-3">
              <div class="flex min-w-0 flex-1 flex-col gap-0.5">
                <span class="text-sm font-semibold" class:line-through={step.done} class:opacity-60={step.done}>
                  {step.done ? "✓ " : ""}{step.title}
                </span>
                {#if !step.done}
                  <span class="text-sm opacity-80">{step.detail}</span>
                {/if}
              </div>
              {#if !step.done}
                <Link to={step.to} class="btn btn-sm">{step.action}</Link>
              {/if}
            </li>
          {/each}
        </ol>
      </Section>
    {/if}

    <Tally {counts} />

    <div class="dash">
      <div class="dash-main">
        <Section title={t("settings.sign_ins.title")}>
          {#snippet actions()}
            <div class="range" role="group" aria-label={t("settings.sign_ins.range")}>
              {#each SPANS as span (span)}
                <button type="button" aria-pressed={days === span} onclick={() => (days = span)}>
                  {t("settings.sign_ins.span", { days: span })}
                </button>
              {/each}
            </div>
          {/snippet}

          {#key days}
            <Loader load={() => api.query(ACTIVITY, { days })}>
              {#snippet children(activity)}
                <BarChart points={plotted(activity.activity)} label={t("settings.sign_ins.chart")} />
              {/snippet}
            </Loader>
          {/key}
        </Section>

        <Section title={t("settings.organizations.title")}>
          {#snippet actions()}
            <Link to="/organizations" class="btn btn-ghost btn-sm">
              {data.tally.organizations > ORGANIZATIONS_SHOWN
                ? t("settings.organizations.all_count", { count: data.tally.organizations })
                : t("settings.organizations.all")}
            </Link>
          {/snippet}

          <Loader load={() => api.query(ORGANIZATIONS)}>
            {#snippet children(held)}
              <Table
                columns={[t("settings.organizations.organization"), { label: t("settings.organizations.members"), right: true }]}
                count={held.organizations.length}
                empty={t("settings.organizations.empty")}
              >
                {#snippet rows()}
                  {#each held.organizations as organization (organization.key)}
                    <Row to={`/organizations/${organization.key}`}>
                      <td>
                        <OrganizationCell {organization} />
                      </td>
                      <td class="text-right text-sm">
                        <OrganizationHeadcount {organization} class="flex flex-col items-end" />
                      </td>
                    </Row>
                  {/each}
                {/snippet}
              </Table>
            {/snippet}
          </Loader>
        </Section>
      </div>

      <div class="dash-side">
        <Loader load={() => api.query(RECENT)}>
          {#snippet children(recent)}
            {#if recent.worrying.length}
              <Section title={t("settings.recent.worrying")}>
                {#snippet actions()}
                  <Link to="/activity" class="btn btn-sm">{t("settings.recent.all")}</Link>
                {/snippet}

                <Events events={recent.worrying} />
              </Section>
            {/if}

            <Section title={t("settings.recent.lately")}>
              {#snippet actions()}
                <Link to="/activity" class="btn btn-ghost btn-sm">{t("settings.recent.all")}</Link>
              {/snippet}

              <Events events={recent.latest} empty={t("settings.recent.empty")} />
            </Section>
          {/snippet}
        </Loader>
      </div>
    </div>
  </Page>
{:else}
  <Page title={t("settings.title")}>
    <Notices feedback={feedback.state} />

    <div class="grid gap-4">
      <Section
        row
        title={t("settings.tenant.title")}
        help={t("settings.tenant.help")}
      >
        <Field label={t("settings.tenant.name")} bind:value={name} onsave={() => update({ name }, t("settings.tenant.renamed"))} />

        <Facts
          rows={[
            { term: t("settings.tenant.subdomain"), value: data.tenant.subdomain, mono: true },
            { term: t("settings.tenant.issuer"), value: boot.issuer, mono: true },
            { term: t("settings.tenant.resource"), value: boot.resource, mono: true },
            { term: t("settings.tenant.since"), value: day(data.tenant.createdAt) },
          ]}
        />
      </Section>

      <Section
        row
        title={t("settings.branding.title")}
        help={t("settings.branding.help")}
      >
        <div class="flex flex-wrap items-center gap-3">
          {#if data.tenant.logoUrl}
            <img src={data.tenant.logoUrl} alt="" width="48" height="48" class="rounded-lg" />
          {/if}

          <label class="btn btn-sm">
            {data.tenant.logoUrl ? t("settings.branding.change_logo") : t("settings.branding.upload_logo")}
            <input type="file" class="hidden" accept="image/png,image/jpeg,image/webp,image/gif" onchange={chooseLogo} />
          </label>

          {#if data.tenant.logoUrl}
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              onclick={() => keys(`mutation { removeTenantLogo { tenant { logoUrl } } }`, {}, t("settings.branding.logo_removed"))}
            >
              {t("settings.branding.remove")}
            </button>
          {/if}
        </div>

        <div class="flex flex-wrap items-center gap-3">
          <label class="flex items-center gap-2 text-sm">
            <input
              type="color"
              value={data.tenant.accentColor ?? "#b3380f"}
              onchange={(event) => update({ accentColor: event.currentTarget.value }, t("settings.branding.color_updated"))}
            />
            {t("settings.branding.accent")}
          </label>

          {#if data.tenant.accentColor}
            <button type="button" class="btn btn-ghost btn-sm" onclick={() => update({ accentColor: "" }, t("settings.branding.color_reset"))}>
              {t("settings.branding.own")}
            </button>
          {/if}
        </div>
      </Section>

      <Section
        row
        title={t("settings.naming.title")}
        help={t("settings.naming.help")}
      >
        <Select
          value={data.tenant.namedBy}
          options={[
            ["nickname", t("settings.naming.nickname")],
            ["email", t("settings.naming.email")],
            ["either", t("settings.naming.either")],
          ]}
          onchange={(namedBy) => update({ namedBy }, t("settings.naming.updated"))}
        />
      </Section>

      <Section
        row
        title={t("settings.policy.title")}
        help={t("settings.policy.help")}
      >
        <Select
          value={data.tenant.signInPolicy?.key ?? ""}
          options={[["", t("settings.policy.built_in")], ...data.signInPolicies.map((policy) => [policy.key, policy.name])]}
          onchange={(signInPolicy) => update({ signInPolicy }, t("settings.policy.updated"))}
        />
      </Section>

      <Section
        row
        title={t("settings.access.title")}
        help={t("settings.access.help")}
      >
        <Switch
          label={t("settings.access.browsers_only")}
          checked={data.tenant.browsersOnly}
          onchange={(browsersOnly) =>
            update({ browsersOnly }, t("settings.access.updated"))}
        />

        <Field
          label={t("settings.access.refused_agents")}
          bind:value={agents}
          placeholder="curl, python-requests"
          onsave={() => update({ blockedAgents: agents }, t("settings.access.updated"))}
        />

        <label class="flex flex-col gap-1.5">
          <span class="field-label">{t("settings.access.risky_networks")}</span>
          <textarea class="textarea w-full font-mono" rows="3" bind:value={networks} placeholder="203.0.113.0/24"></textarea>
          <span class="hint">
            {t("settings.access.risky_hint")}
          </span>
        </label>
        <div>
          <button type="button" class="btn btn-sm" onclick={() => update({ riskyNetworks: networks }, t("settings.access.networks_saved"))}>
            {t("settings.access.save_networks")}
          </button>
        </div>
      </Section>

      <Section
        row
        title={t("settings.idle.title")}
        help={t("settings.idle.help")}
      >
        <div class="grid gap-3 sm:grid-cols-2">
          <Select
            label={t("settings.idle.suspend")}
            value={data.tenant.suspendAfter ?? 0}
            options={choices(SUSPEND_AFTER, data.tenant.suspendAfter)}
            onchange={(days) => update({ suspendAfter: Number(days) }, t("settings.idle.updated"))}
          />

          <Select
            label={t("settings.idle.delete")}
            value={data.tenant.deleteAfter ?? 0}
            options={choices(DELETE_AFTER, data.tenant.deleteAfter).map(([days, label]) => [
              days,
              label,
              days > 0 && days <= (data.tenant.suspendAfter ?? 0),
            ])}
            onchange={(days) => deleteAfter(Number(days))}
          />
        </div>
      </Section>

      <Section
        row
        title={t("settings.retention.title")}
        help={t("settings.retention.help")}
      >
        <Select
          value={data.tenant.eventRetentionDays}
          options={choices(RETENTION, data.tenant.eventRetentionDays)}
          onchange={(days) => update({ eventRetentionDays: Number(days) }, t("settings.retention.updated"))}
        />
      </Section>

      <Section
        row
        title={t("settings.registration.title")}
        help={t("settings.registration.help")}
      >
        <Select
          value={data.tenant.dynamicRegistration}
          options={[
            ["off", t("settings.registration.off")],
            ["anything", t("settings.registration.on")],
            ["bounded", t("settings.registration.bounded")],
          ]}
          onchange={(dynamicRegistration) =>
            update({ dynamicRegistration }, t("settings.registration.updated"))}
        />

        {#if data.tenant.dynamicRegistration === "bounded"}
          <ScopesEditor
            value={data.tenant.dynamicClientScopes ?? []}
            available={data.scopesSupported}
            onchange={(dynamicClientScopes) => update({ dynamicClientScopes }, t("settings.registration.ceiling_updated"))}
          />
        {/if}
      </Section>

      {#if data.namespaces.length}
        <Namespaces {api} rows={data.namespaces} onreleased={load} showClient />
      {/if}

      <Section title={t("settings.keys.title")}>
        {#snippet actions()}
          <button type="button" class="btn btn-sm" onclick={stage}>{t("settings.keys.stage")}</button>
          <button type="button" class="btn btn-sm btn-outline" onclick={rotate}>{t("settings.keys.rotate")}</button>
          <Select
            name={t("settings.keys.schedule")}
            value={String(data.tenant.keyRotationDays ?? 0)}
            options={[0, 30, 90, 180, 365].map((days) => [
              String(days),
              days ? t("settings.keys.every", { count: days }) : t("settings.keys.by_hand"),
            ])}
            onchange={(days) => update({ keyRotationDays: Number(days) }, t("settings.keys.scheduled"))}
          />
        {/snippet}

        <div class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>{t("settings.keys.key")}</th>
                <th class="hidden sm:table-cell">{t("settings.keys.algorithm")}</th>
                <th>{t("settings.keys.state")}</th>
                <th class="hidden sm:table-cell">{t("settings.keys.activated")}</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {#each data.tenant.signingKeys as key (key.kid)}
                <tr>
                  <td class="font-mono text-xs">{key.kid.slice(0, 8)}</td>
                  <td class="hidden text-xs sm:table-cell">{key.algorithm}</td>
                  <td><span class="badge badge-sm {BADGE[key.state]}">{BADGE[key.state] ? t(`settings.keys.states.${key.state}`) : key.state}</span></td>
                  <td class="hidden text-xs opacity-85 sm:table-cell">
                    {#if key.state === "retiring"}
                      {t("settings.keys.until", { day: day(key.retiredAt) })}
                    {:else}
                      {day(key.activatedAt, t("settings.keys.not_yet"))}
                    {/if}
                  </td>
                  <td class="text-right whitespace-nowrap">
                    {#if key.state === "staged"}
                      <button type="button" class="btn btn-xs" onclick={() => activate(key.kid)}>
                        {t("settings.keys.activate")}
                      </button>
                      <button
                        type="button"
                        class="btn btn-xs btn-ghost"
                        onclick={() => discard(key.kid)}
                      >
                        {t("settings.keys.discard")}
                      </button>
                    {/if}
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </Section>

      <GroupsSection {api} />

      <DomainsSection {api} />
    </div>
  </Page>
{/if}
