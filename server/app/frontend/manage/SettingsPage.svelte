<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { t } from "./lib/copy.js";
  import { day } from "./lib/format.js";
  import DomainsSection from "./DomainsSection.svelte";
  import GroupsSection from "./GroupsSection.svelte";
  import Namespaces from "./Namespaces.svelte";
  import ScopesEditor from "./ScopesEditor.svelte";
  import Section from "./ui/Section.svelte";
  import Select from "./ui/Select.svelte";
  import Facts from "./ui/Facts.svelte";
  import Field from "./ui/Field.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api, boot } = $props();

  const QUERY = `
    query Tenant {
      tenant {
        uuid subdomain name dynamicRegistration dynamicClientScopes createdAt mails accentColor logoUrl keyRotationDays
        eventRetentionDays invitationLifetime organizationInvitationLifetime passwordResetLifetime emailVerificationLifetime
        signingKeys { kid algorithm activatedAt retiredAt state }
      }
      viewer { identifier scopes }
      namespaces {
        name resource claimedAt releasable
        client { clientId name }
      }
      scopesSupported
    }
  `;

  const RETENTION = [
    [30, t("settings.retention.days_30")],
    [90, t("settings.retention.days_90")],
    [180, t("settings.retention.days_180")],
    [365, t("settings.retention.a_year")],
    [1095, t("settings.retention.three_years")],
    [2555, t("settings.retention.seven_years")],
  ];

  const MINUTE = 60;
  const HOUR = 60 * MINUTE;
  const DAY = 24 * HOUR;

  const LINKS = [
    ["invitationLifetime", "invitation", 7 * DAY, [DAY, 3 * DAY, 7 * DAY, 14 * DAY, 30 * DAY]],
    ["organizationInvitationLifetime", "organization_invitation", 14 * DAY, [DAY, 3 * DAY, 7 * DAY, 14 * DAY, 30 * DAY]],
    ["passwordResetLifetime", "password_reset", 30 * MINUTE, [15 * MINUTE, 30 * MINUTE, HOUR, 4 * HOUR, DAY]],
    ["emailVerificationLifetime", "email_verification", 2 * DAY, [HOUR, DAY, 2 * DAY, 7 * DAY, 14 * DAY]],
  ];

  function lasting(seconds) {
    if (seconds % DAY === 0) return t("links.days", { count: seconds / DAY });
    if (seconds % HOUR === 0) return t("links.hours", { count: seconds / HOUR });

    return t("links.minutes", { count: Math.round(seconds / MINUTE) });
  }

  const lifetimes = (presets, usual, held) =>
    (presets.includes(held) ? presets : [...presets, held].sort((a, b) => a - b)).map((seconds) => [
      String(seconds),
      seconds === usual ? t("links.default", { length: lasting(seconds) }) : lasting(seconds),
    ]);

  const choices = (listed, held) =>
    !held || listed.some(([days]) => days === held) ? listed : [...listed, [held, t("settings.after_days", { days: held })]];

  const BADGE = {
    staged: "badge-warning",
    active: "badge-success",
    retiring: "badge-info",
    retired: "badge-ghost",
  };

  const feedback = createFeedback();

  let data = $state(null);
  let name = $state("");
  let loading = $state(true);

  async function load() {
    loading = true;

    try {
      data = await api.query(QUERY);
      name = data.tenant.name;
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
            $eventRetentionDays: Int, $accentColor: String, $keyRotationDays: Int,
            $invitationLifetime: Int, $organizationInvitationLifetime: Int, $passwordResetLifetime: Int, $emailVerificationLifetime: Int
          ) {
            updateTenant(
              name: $name
              dynamicClientScopes: $dynamicClientScopes
              dynamicRegistration: $dynamicRegistration
              eventRetentionDays: $eventRetentionDays
              accentColor: $accentColor
              keyRotationDays: $keyRotationDays
              invitationLifetime: $invitationLifetime
              organizationInvitationLifetime: $organizationInvitationLifetime
              passwordResetLifetime: $passwordResetLifetime
              emailVerificationLifetime: $emailVerificationLifetime
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
        title={t("settings.retention.title")}
        help={t("settings.retention.help")}
      >
        <Select
          value={data.tenant.eventRetentionDays}
          options={choices(RETENTION, data.tenant.eventRetentionDays)}
          onchange={(days) => update({ eventRetentionDays: Number(days) }, t("settings.retention.updated"))}
        />
      </Section>

      <Section row title={t("links.title")} help={t("links.help")}>
        <div class="grid gap-3 sm:grid-cols-2">
          {#each LINKS as [field, key, usual, presets] (field)}
            <Select
              label={t(`links.${key}`)}
              value={String(data.tenant[field])}
              options={lifetimes(presets, usual, data.tenant[field])}
              onchange={(seconds) => update({ [field]: Number(seconds) }, t("links.updated"))}
            />
          {/each}
        </div>
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
        <Namespaces {api} rows={data.namespaces} onreleased={load} showClient row />
      {/if}

      <Section row title={t("settings.keys.title")} help={t("settings.keys.help")}>
        <ul class="compact-list">
          {#each data.tenant.signingKeys as key (key.kid)}
            <li class="flex-wrap">
              <code class="font-mono text-sm">{key.kid.slice(0, 8)}</code>
              <span class="badge badge-sm {BADGE[key.state]}">{BADGE[key.state] ? t(`settings.keys.states.${key.state}`) : key.state}</span>
              <span class="hint text-xs">
                {key.algorithm} ·
                {#if key.state === "retiring"}
                  {t("settings.keys.until", { day: day(key.retiredAt) })}
                {:else}
                  {day(key.activatedAt, t("settings.keys.not_yet"))}
                {/if}
              </span>

              {#if key.state === "staged"}
                <div class="ml-auto flex gap-1">
                  <button type="button" class="btn btn-xs" onclick={() => activate(key.kid)}>{t("settings.keys.activate")}</button>
                  <button type="button" class="btn btn-xs btn-ghost" onclick={() => discard(key.kid)}>{t("settings.keys.discard")}</button>
                </div>
              {/if}
            </li>
          {/each}
        </ul>

        <div class="flex flex-wrap items-center gap-2">
          <Select
            name={t("settings.keys.schedule")}
            value={String(data.tenant.keyRotationDays ?? 0)}
            options={[0, 30, 90, 180, 365].map((days) => [
              String(days),
              days ? t("settings.keys.every", { count: days }) : t("settings.keys.by_hand"),
            ])}
            onchange={(days) => update({ keyRotationDays: Number(days) }, t("settings.keys.scheduled"))}
          />
          <button type="button" class="btn btn-sm" onclick={stage}>{t("settings.keys.stage")}</button>
          <button type="button" class="btn btn-sm btn-ghost" onclick={rotate}>{t("settings.keys.rotate")}</button>
        </div>
      </Section>

      <GroupsSection {api} />

      <DomainsSection {api} />
    </div>
  </Page>
{/if}
