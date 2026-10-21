<script>
  import { t } from "./lib/copy.js";
  import { moment, since } from "./lib/format.js";
  import Events from "./Events.svelte";
  import OrganizationCell from "./OrganizationCell.svelte";
  import OrganizationHeadcount from "./OrganizationHeadcount.svelte";
  import BarChart from "./ui/BarChart.svelte";
  import Link from "./ui/Link.svelte";
  import Loader from "./ui/Loader.svelte";
  import Page from "./ui/Page.svelte";
  import Row from "./ui/Row.svelte";
  import Section from "./ui/Section.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Table from "./ui/Table.svelte";
  import Tally from "./ui/Tally.svelte";

  let { api, boot } = $props();

  const ORGANIZATIONS_SHOWN = 5;

  const QUERY = `
    query Overview($since: ISO8601DateTime!) {
      tenant { name mails }
      tally { actors clients devices organizations }
      waiting: actorCount(pendingApproval: true)
      help: actorCount(recoveryRequested: true)
      worrying: eventCount(grave: true, since: $since)
      gravest: events(grave: true, since: $since, limit: 1) { id label createdAt }
      latest: events(limit: 40) {
        id action label createdAt ipAddress details
        actor { uuid identifier }
        by { uuid identifier }
        client { clientId name }
        device { id label }
      }
      organizations(limit: ${ORGANIZATIONS_SHOWN}) { key name memberCount ownerCount pendingCount }
      health { name status summary details checkedAt changedAt }
      release { version url operatorStep }
    }
  `;

  const RUN_CHECKS = `
    mutation RunHealthChecks {
      runHealthChecks { health { name status summary details checkedAt changedAt } }
    }
  `;

  const TONES = { ok: "good", warning: "warn", failing: "bad" };

  const ACTIVITY = `
    query Activity($days: Int) {
      activity(days: $days) { date signIns }
    }
  `;

  const SPANS = [7, 30, 90];
  const DAY = 24 * 60 * 60 * 1000;
  const MARK = new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short" });
  const SKIPPED = "masks:manage:skipped";

  let data = $state(null);
  let failure = $state(null);
  let days = $state(30);
  let skipped = $state([]);
  let checking = $state(false);
  let checkFailure = $state(null);

  try {
    skipped = JSON.parse(localStorage.getItem(SKIPPED) ?? "[]");
  } catch {}

  function skip(key) {
    skipped = [...skipped, key];

    try {
      localStorage.setItem(SKIPPED, JSON.stringify(skipped));
    } catch {}
  }

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

  const needs = $derived(
    data
      ? [
          data.waiting && {
            key: "waiting",
            tone: "warn",
            title: t("settings.needs.waiting", { count: data.waiting }),
            to: "/actors?lens=waiting",
          },
          data.help && {
            key: "help",
            tone: "warn",
            title: t("settings.needs.help", { count: data.help }),
            to: "/actors?lens=help",
          },
          data.worrying && {
            key: "worrying",
            tone: "bad",
            title: t("settings.needs.worrying", { count: data.worrying }),
            detail: t("settings.needs.latest", { label: data.gravest[0].label, when: since(data.gravest[0].createdAt) }),
            to: "/activity?grave=1",
          },
        ].filter(Boolean)
      : [],
  );

  const starting = $derived(
    data
      ? [
          !data.tenant.mails && {
            key: "mail",
            title: t("settings.starting.mail.title"),
            detail: t("settings.starting.mail.detail"),
            to: "/messages",
            action: t("settings.starting.mail.action"),
          },
          data.tally.clients === 0 && {
            key: "client",
            title: t("settings.starting.client.title"),
            detail: t("settings.starting.client.detail"),
            to: "/clients",
            action: t("settings.starting.client.action"),
          },
          data.tally.actors <= 1 && {
            key: "invite",
            title: t("settings.starting.invite.title"),
            detail: t("settings.starting.invite.detail"),
            to: "/actors",
            action: t("settings.starting.invite.action"),
          },
        ].filter((step) => step && !skipped.includes(step.key))
      : [],
  );

  const plotted = (rows) =>
    rows.map((row) => ({
      key: row.date,
      value: row.signIns,
      label: MARK.format(new Date(`${row.date}T00:00:00`)),
    }));

  const checkedAt = $derived(data?.health.length ? data.health.map((check) => check.checkedAt).sort().at(-1) : null);

  function sentence(check) {
    const details = check.details ?? {};
    const values = {
      ...details,
      jobs: Array.isArray(details.jobs) ? details.jobs.join(", ") : details.jobs,
      domains: Array.isArray(details.domains) ? details.domains.join(", ") : details.domains,
      since: details.since ? moment(details.since) : details.since,
    };

    return t(`health.checks.${check.name}.${check.summary}`, values);
  }

  async function runChecks() {
    checking = true;
    checkFailure = null;

    try {
      const answer = await api.query(RUN_CHECKS);
      data = { ...data, health: answer.runHealthChecks.health };
    } catch (thrown) {
      checkFailure = thrown.message;
    } finally {
      checking = false;
    }
  }

  async function load() {
    try {
      data = await api.query(QUERY, { since: new Date(Date.now() - DAY).toISOString() });
    } catch (thrown) {
      failure = thrown.message;
    }
  }

  load();
</script>

{#if !data && !failure}
  <Spinner />
{:else if !data}
  <div class="alert alert-error alert-soft text-sm" role="alert">{failure}</div>
{:else}
  <Page title={data.tenant.name} id={boot.issuer} hero>
    {#if needs.length || starting.length || data.release}
      <div class="flex flex-col gap-2">
        {#if data.release}
          <div class="callout callout-info" role="status">
            <div class="callout-words">
              <strong>{t("health.release.available", { version: data.release.version })}</strong>
              {#if data.release.operatorStep}<span class="hint">{t("health.release.operator")}</span>{/if}
            </div>
            <div class="callout-actions">
              <a class="btn btn-sm" href={data.release.url} target="_blank" rel="noreferrer noopener">{t("health.release.notes")}</a>
            </div>
          </div>
        {/if}

        {#each needs as need (need.key)}
          <div class="callout callout-{need.tone}" role="status">
            <div class="callout-words">
              <strong>{need.title}</strong>
              {#if need.detail}<span class="hint">{need.detail}</span>{/if}
            </div>
            <div class="callout-actions">
              <Link to={need.to} class="btn btn-sm">{t("settings.needs.review")}</Link>
            </div>
          </div>
        {/each}

        {#each starting as step (step.key)}
          <div class="callout callout-quiet">
            <div class="callout-words">
              <strong>{step.title}</strong>
              <span class="hint">{step.detail}</span>
            </div>
            <div class="callout-actions">
              <Link to={step.to} class="btn btn-sm">{step.action}</Link>
              <button type="button" class="btn btn-ghost btn-sm" onclick={() => skip(step.key)}>
                {t("settings.starting.hide")}
              </button>
            </div>
          </div>
        {/each}
      </div>
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
      </div>

      <div class="dash-side">
        <Section title={t("health.title")} lede={t("health.lede")}>
          {#snippet actions()}
            <button type="button" class="btn btn-ghost btn-sm" disabled={checking} onclick={runChecks}>
              {checking ? t("health.checking") : t("health.check_now")}
            </button>
          {/snippet}

          {#if checkFailure}
            <div class="alert alert-error alert-soft text-sm" role="alert">{t("health.failed", { failure: checkFailure })}</div>
          {/if}

          {#if data.health.length}
            <ul class="compact-list" aria-label={t("health.title")}>
              {#each data.health as check (check.name)}
                <li class="items-start">
                  <span class="mark mark-{TONES[check.status]} mt-1" role="img" aria-label={t(`health.statuses.${check.status}`)} title={t(`health.statuses.${check.status}`)}>
                    <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><circle cx="10" cy="10" r="5" /></svg>
                  </span>
                  <div class="flex min-w-0 flex-col">
                    <span class="text-sm font-medium">{t(`health.checks.${check.name}.title`)}</span>
                    <span class="text-sm">{sentence(check)}</span>
                    {#if check.status !== "ok"}
                      <span class="hint text-xs">{t(`health.checks.${check.name}.advice`, check.details ?? {})}</span>
                    {/if}
                  </div>
                </li>
              {/each}
            </ul>
            <p class="hint text-xs">{t("health.checked", { when: since(checkedAt) })}</p>
          {:else}
            <p class="hint">{t("health.never")}</p>
          {/if}
        </Section>

        <Section title={t("settings.organizations.title")}>
          {#snippet actions()}
            <Link to="/organizations" class="btn btn-ghost btn-sm">
              {data.tally.organizations > ORGANIZATIONS_SHOWN
                ? t("settings.organizations.all_count", { count: data.tally.organizations })
                : t("settings.organizations.all")}
            </Link>
          {/snippet}

          {#if data.organizations.length}
            <Table columns={[t("settings.organizations.organization"), { label: t("settings.organizations.members"), right: true }]} count={data.organizations.length}>
              {#snippet rows()}
                {#each data.organizations as organization (organization.key)}
                  <Row to={`/organizations/${organization.key}`}>
                    <td><OrganizationCell {organization} /></td>
                    <td class="text-right text-sm whitespace-nowrap">
                      <OrganizationHeadcount {organization} class="flex flex-col items-end" />
                    </td>
                  </Row>
                {/each}
              {/snippet}
            </Table>
          {:else}
            <p class="hint">{t("settings.organizations.empty")}</p>
          {/if}
        </Section>
      </div>
    </div>

    <Section title={t("settings.recent.title")}>
      {#snippet actions()}
        <Link to="/activity" class="btn btn-ghost btn-sm">{t("settings.recent.all")}</Link>
      {/snippet}

      <Events events={data.latest} empty={t("settings.recent.empty")} limit={8} collapse />
    </Section>
  </Page>
{/if}
