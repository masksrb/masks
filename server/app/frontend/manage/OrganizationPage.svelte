<script>
  import { t } from "./lib/copy.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, since } from "./lib/format.js";
  import { useRouter } from "./lib/router.svelte.js";
  import Section from "./ui/Section.svelte";
  import Facts from "./ui/Facts.svelte";
  import Field from "./ui/Field.svelte";
  import Events from "./Events.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Select from "./ui/Select.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Table from "./ui/Table.svelte";
  import Tally from "./ui/Tally.svelte";

  let { api, organizationKey } = $props();

  const router = useRouter();
  const feedback = createFeedback();

  const BUILT_IN = ["owner", "member"];

  const QUERY = `
    query Organization($key: ID!) {
      organization(key: $key) {
        uuid key name roles archivedAt createdAt
        memberCount ownerCount pendingCount liveTokenCount
        signInPolicy { key }
        providers { key name roleClaim roleMap unmappedRole }
        domains { domain verifiedAt provider { name } }
        provisioningTokens { id }
        members {
          role pending provisioned invitedAs invitedAt expiresAt expired createdAt
          invitedBy { identifier }
          actor { uuid identifier }
        }
        events {
          id action label createdAt ipAddress details
          actor { uuid identifier } by { uuid identifier } client { clientId name } device { id label }
        }
      }
      signInPolicies { key name }
      providers { key name organization { key } }
    }
  `;

  const LENSES = [
    ["all", t("organization.lenses.all")],
    ["owners", t("organization.lenses.owners")],
    ["invited", t("organization.lenses.invited")],
  ];

  let organization = $state(null);
  let policies = $state([]);
  let providers = $state([]);
  const idle = () => ({ provider: "", roleClaim: "", roleMap: "", unmappedRole: "" });

  let handing = $state(idle());
  let loading = $state(true);
  let busy = $state(false);
  let adding = $state(null);
  let lens = $state("all");
  let naming = $state("");
  let role = $state("");
  let invited = $state(null);

  async function load() {
    loading = true;

    const answer = await feedback.attempt(() => api.query(QUERY, { key: organizationKey }));

    loading = false;

    if (!answer) return;

    organization = answer.organization;
    policies = answer.signInPolicies;
    providers = answer.providers;

    if (organization) naming = organization.name;
  }

  load();

  const roleOptions = $derived((organization?.roles ?? []).map((held) => [held, held]));

  const holding = $derived(
    Object.fromEntries(
      (organization?.roles ?? []).map((held) => [
        held,
        organization.members.filter((member) => member.role === held).length,
      ]),
    ),
  );

  const shown = $derived(
    (organization?.members ?? [])
      .filter((member) =>
        lens === "owners" ? member.role === "owner" && !member.pending : lens === "invited" ? member.pending : true,
      )
      .toSorted(
        (a, b) =>
          Number(a.pending) - Number(b.pending) ||
          Number(b.role === "owner") - Number(a.role === "owner") ||
          named(a).localeCompare(named(b)),
      ),
  );

  const revoking = (plain, tokens) =>
    organization.liveTokenCount
      ? t(tokens, { organization: organization.name, count: organization.liveTokenCount })
      : t(plain, { organization: organization.name });

  const counts = $derived(
    organization
      ? [
          {
            label: t("organization.counts.members", { count: organization.memberCount }),
            value: organization.memberCount,
          },
          {
            label: t("organization.counts.owners", { count: organization.ownerCount }),
            value: organization.ownerCount,
          },
          { label: t("organization.counts.invitations"), value: organization.pendingCount },
          { label: t("organization.counts.live_tokens"), value: organization.liveTokenCount },
        ]
      : [],
  );

  const facts = $derived(
    organization
      ? [
          { term: t("organization.facts.key"), value: organization.key, mono: true },
          { term: t("organization.facts.id"), value: organization.uuid, mono: true },
          { term: t("organization.facts.asked_for_with"), value: `organization=${organization.key}`, mono: true },
          { term: t("organization.facts.created"), value: day(organization.createdAt) },
        ]
      : [],
  );

  function named(member) {
    return member.pending ? (member.invitedAs ?? member.actor.identifier) : member.actor.identifier;
  }

  function lastOwner(member) {
    return member.role === "owner" && !member.pending && organization.ownerCount === 1;
  }

  function status(member) {
    if (member.expired) return t("organization.status.expired", { when: since(member.expiresAt) });

    if (member.pending) {
      return member.invitedBy
        ? t("organization.status.invited_by", {
            when: since(member.invitedAt),
            by: member.invitedBy.identifier,
          })
        : t("organization.status.invited", { when: since(member.invitedAt) });
    }

    return t(member.provisioned ? "organization.status.from_directory" : "organization.status.since", {
      day: day(member.createdAt),
    });
  }

  async function run(query, variables, notice) {
    busy = true;

    const answer = await feedback.attempt(() => api.query(query, variables), notice);

    busy = false;

    if (answer) await load();

    return answer;
  }

  function openAdding() {
    adding = { email: "", role: "member" };
    invited = null;
    feedback.clear();
  }

  async function add() {
    const email = adding.email.trim();

    invited = null;

    const answer = await run(
      `mutation Add($organization: ID!, $email: String!, $role: String!) {
        addMember(organization: $organization, email: $email, role: $role) { delivered url }
      }`,
      { organization: organization.key, email, role: adding.role },
      t("organization.notices.invited", { email, role: adding.role }),
    );

    if (!answer) return;

    adding = null;

    if (!answer.addMember.delivered && answer.addMember.url) invited = answer.addMember.url;
  }

  function setRole(member, chosen) {
    run(
      `mutation Role($organization: ID!, $uuid: ID!, $role: String!) {
        setMemberRole(organization: $organization, uuid: $uuid, role: $role) { membership { role } }
      }`,
      { organization: organization.key, uuid: member.actor.uuid, role: chosen },
      t("organization.notices.role_set", { name: named(member), role: chosen }),
    );
  }

  function remove(member) {
    const question = member.pending
      ? t("organization.questions.withdraw", { name: named(member) })
      : t("organization.questions.remove", { name: named(member), organization: organization.name });

    if (!confirm(question)) return;

    run(
      `mutation Remove($organization: ID!, $uuid: ID!) {
        removeMember(organization: $organization, uuid: $uuid) { organization { key } }
      }`,
      { organization: organization.key, uuid: member.actor.uuid },
      member.pending
        ? t("organization.notices.withdrawn", { name: named(member) })
        : t("organization.notices.removed", { name: named(member), organization: organization.name }),
    );
  }

  function resend(member) {
    run(
      `mutation Resend($organization: ID!, $uuid: ID!) {
        resendOrganizationInvitation(organization: $organization, uuid: $uuid) { delivered }
      }`,
      { organization: organization.key, uuid: member.actor.uuid },
      t("organization.notices.resent", { name: named(member) }),
    );
  }

  function saveRoles(roles, notice) {
    return run(
      `mutation Roles($key: ID!, $roles: [String!]) {
        updateOrganization(key: $key, roles: $roles) { organization { key } }
      }`,
      { key: organization.key, roles },
      notice,
    );
  }

  const custom = $derived((organization?.roles ?? []).filter((held) => !BUILT_IN.includes(held)));

  async function addRole() {
    const chosen = role.trim().toLowerCase();

    if (!chosen) return;

    if (
      await saveRoles(
        [...custom, chosen],
        t("organization.notices.role_added", { organization: organization.name, role: chosen }),
      )
    )
      role = "";
  }

  function dropRole(held) {
    saveRoles(
      custom.filter((kept) => kept !== held),
      t("organization.notices.role_dropped", { organization: organization.name, role: held }),
    );
  }

  function rename() {
    run(
      `mutation Rename($key: ID!, $name: String) {
        updateOrganization(key: $key, name: $name) { organization { key } }
      }`,
      { key: organization.key, name: naming.trim() },
      t("organization.notices.saved"),
    );
  }

  const lines = (map) =>
    Object.entries(map ?? {})
      .map(([group, held]) => `${group} = ${held}`)
      .join("\n");

  const parsed = (text) =>
    Object.fromEntries(
      text
        .split("\n")
        .map((line) => line.split("="))
        .filter((parts) => parts.length === 2 && parts[0].trim() && parts[1].trim())
        .map(([group, held]) => [group.trim(), held.trim()]),
    );

  const handable = $derived(
    providers.filter((provider) => !provider.organization),
  );

  function pickProvider(key) {
    const held = organization.providers.find((provider) => provider.key === key);

    handing = {
      provider: key,
      roleClaim: held?.roleClaim ?? "",
      roleMap: lines(held?.roleMap),
      unmappedRole: held?.unmappedRole ?? "",
    };
  }

  function handOver() {
    run(
      `mutation Hand($key: ID!, $organization: ID, $roleClaim: String, $roleMap: JSON, $unmappedRole: String) {
        setProviderOrganization(key: $key, organization: $organization, roleClaim: $roleClaim, roleMap: $roleMap, unmappedRole: $unmappedRole) {
          provider { key }
        }
      }`,
      {
        key: handing.provider,
        organization: organization.key,
        roleClaim: handing.roleClaim.trim() || null,
        roleMap: parsed(handing.roleMap),
        unmappedRole: handing.unmappedRole || null,
      },
      t("organization.notices.provider_saved"),
    ).then((answer) => {
      if (answer) handing = idle();
    });
  }

  function handBack(provider) {
    if (
      !confirm(
        t("organization.questions.hand_back", { provider: provider.name, organization: organization.name }),
      )
    )
      return;

    run(
      `mutation Back($key: ID!) { setProviderOrganization(key: $key, organization: null) { provider { key } } }`,
      { key: provider.key },
      t("organization.notices.provider_back", { provider: provider.name }),
    );
  }

  function setPolicy(key) {
    run(
      `mutation Policy($key: ID!, $policy: ID!) {
        updateOrganization(key: $key, signInPolicy: $policy) { organization { key } }
      }`,
      { key: organization.key, policy: key },
      t("organization.notices.saved"),
    );
  }

  async function archive() {
    if (!confirm(revoking("organization.questions.archive", "organization.questions.archive_tokens"))) return;

    await run(
      `mutation Archive($key: ID!) { archiveOrganization(key: $key) { organization { key } } }`,
      { key: organization.key },
      t("organization.notices.archived", { organization: organization.name }),
    );
  }

  function restore() {
    run(
      `mutation Restore($key: ID!) { restoreOrganization(key: $key) { organization { key } } }`,
      { key: organization.key },
      t("organization.notices.restored", { organization: organization.name }),
    );
  }
</script>

<Page
  title={organization?.name ?? t("organization.title")}
  id={organization?.key}
  back={{ to: "/organizations", label: t("organization.back") }}
  lede={organization
    ? organization.archivedAt
      ? t("organization.archived_lede", { when: since(organization.archivedAt) })
      : t("organization.lede", { key: organization.key })
    : null}
>
  <Notices feedback={feedback.state} />

  {#if loading && !organization}
    <Spinner />
  {:else if !organization}
    <p class="hint">{t("organization.missing", { key: organizationKey })}
      <Link to="/organizations">{t("organization.all")}</Link></p>
  {:else}
    {#if organization.archivedAt}
      <div class="alert alert-warning alert-soft flex flex-wrap items-center justify-between gap-3" role="status">
        <span>{t("organization.archived_alert", { day: day(organization.archivedAt) })}</span>
        <button type="button" class="btn btn-sm" disabled={busy} onclick={restore}>{t("organization.restore")}</button>
      </div>
    {/if}

    {#if !organization.archivedAt && organization.ownerCount === 0}
      <div class="alert alert-warning alert-soft" role="status">
        {t("organization.ownerless", { organization: organization.name })}
      </div>
    {/if}

    <Tally {counts} />

    {#if invited}
      <div class="alert alert-info alert-soft flex-col items-start gap-2" role="status">
        <span class="font-medium">{t("organization.invitation_link")}</span>
        <code class="font-mono text-xs break-all">{invited}</code>
      </div>
    {/if}

    <Section
      title={t("organization.members.title")}
      lede={t("organization.members.lede")}
    >
      {#snippet actions()}
        <div class="range" role="group" aria-label={t("organization.members.who")}>
          {#each LENSES as [key, label] (key)}
            <button type="button" aria-pressed={lens === key} onclick={() => (lens = key)}>{label}</button>
          {/each}
        </div>
        {#if !organization.archivedAt}
          <button type="button" class="btn btn-primary btn-sm" onclick={openAdding}>{t("organization.members.add")}</button>
        {/if}
      {/snippet}

      {#if adding}
        <div class="grid gap-3 sm:grid-cols-[minmax(0,1fr)_10rem_auto] sm:items-end">
          <Field label={t("organization.members.email")} type="email" bind:value={adding.email} placeholder="person@example.com" />
          <Select label={t("organization.members.role")} value={adding.role} options={roleOptions} onchange={(chosen) => (adding.role = chosen)} />
          <div class="flex gap-2">
            <button type="button" class="btn btn-primary btn-sm" disabled={busy || !adding.email.trim()} onclick={add}>
              {t("organization.members.invite")}
            </button>
            <button type="button" class="btn btn-ghost btn-sm" onclick={() => (adding = null)}>{t("organization.members.cancel")}</button>
          </div>
        </div>
        <p class="hint">
          {t("organization.members.hint")}
        </p>
      {/if}

      <Table
        columns={[
          t("organization.members.person"),
          { label: t("organization.members.role"), hide: true },
          { label: "", right: true, hide: true },
        ]}
        count={shown.length}
        empty={t(`organization.members.empty.${lens}`)}
      >
        {#snippet rows()}
          {#each shown as member (member.actor.uuid)}
            <tr>
              <td class="w-full min-w-0">
                <div class="flex min-w-0 flex-col gap-0.5">
                  <span class="flex flex-wrap items-center gap-2">
                    <Link to={`/actors/${member.actor.uuid}`} class="link link-hover font-medium break-all">
                      {named(member)}
                    </Link>
                    {#if member.expired}<span class="badge badge-sm badge-error badge-soft">{t("organization.members.expired")}</span>
                    {:else if member.pending}<span class="badge badge-sm badge-warning badge-soft">{t("organization.members.invited")}</span>{/if}
                    {#if lastOwner(member)}<span class="badge badge-sm badge-ghost">{t("organization.members.last_owner")}</span>{/if}
                  </span>
                  <span class="hint">{status(member)}</span>
                  <div class="mt-2 flex flex-wrap items-center gap-2 md:hidden">
                    <div class="min-w-28 flex-1 basis-28">{@render roleOf(member)}</div>
                    <div class="-me-3 flex shrink-0">{@render removeOf(member)}</div>
                  </div>
                </div>
              </td>
              <td class="hidden w-44 min-w-44 md:table-cell">
                {@render roleOf(member)}
              </td>
              <td class="hidden text-right whitespace-nowrap md:table-cell">
                {@render removeOf(member)}
              </td>
            </tr>
          {/each}
        {/snippet}
      </Table>
    </Section>

    <div class="grid items-start gap-4 lg:grid-cols-2">
      <div class="flex flex-col gap-4">
        <Section
          title={t("organization.signing_in.title")}
          lede={t("organization.signing_in.lede")}
        >
          <Select
            label={t("organization.signing_in.policy")}
            value={organization.signInPolicy?.key ?? ""}
            options={[["", t("organization.signing_in.inherited")], ...policies.map((policy) => [policy.key, policy.name])]}
            disabled={busy}
            onchange={setPolicy}
          />

          <div class="flex flex-col gap-2">
            <span class="legend">{t("organization.signing_in.providers")}</span>

            {#each organization.providers as provider (provider.key)}
              <div class="flex flex-wrap items-center justify-between gap-2 sheet p-3">
                <div class="flex min-w-0 flex-col">
                  <span class="font-medium">{provider.name}</span>
                  <span class="hint">
                    {t("organization.signing_in.joins_as", {
                      mapping: Object.keys(provider.roleMap).length
                        ? Object.entries(provider.roleMap)
                            .map(([group, held]) => `${group} → ${held}`)
                            .join(", ")
                        : t("organization.signing_in.no_groups_mapped"),
                      role: provider.unmappedRole ?? "member",
                    })}
                  </span>
                </div>
                <div class="flex gap-2">
                  <button type="button" class="btn btn-sm" disabled={busy} onclick={() => pickProvider(provider.key)}>{t("organization.signing_in.edit")}</button>
                  <button type="button" class="btn btn-ghost btn-sm" disabled={busy} onclick={() => handBack(provider)}>
                    {t("organization.signing_in.hand_back")}
                  </button>
                </div>
              </div>
            {:else}
              <p class="hint">
                {t("organization.signing_in.no_providers")}
              </p>
            {/each}

            {#if handable.length && !handing.provider}
              <Select
                value=""
                name={t("organization.signing_in.give_provider")}
                options={[
                  ["", t("organization.signing_in.give_provider")],
                  ...handable.map((provider) => [provider.key, provider.name]),
                ]}
                onchange={pickProvider}
              />
            {/if}
          </div>

          {#if handing.provider}
            <div class="flex flex-col gap-3 sheet p-3">
              <span class="font-medium">
                {providers.find((provider) => provider.key === handing.provider)?.name ?? handing.provider}
              </span>
              <div class="grid gap-3 sm:grid-cols-2">
                <Field label={t("organization.signing_in.groups_claim")} bind:value={handing.roleClaim} placeholder="groups" />
                <Select
                  label={t("organization.signing_in.unmapped_role")}
                  value={handing.unmappedRole}
                  options={[["", "member"], ...roleOptions.filter(([held]) => held !== "member")]}
                  onchange={(chosen) => (handing.unmappedRole = chosen)}
                />
              </div>
              <label class="flex flex-col gap-1.5">
                <span class="field-label">{t("organization.signing_in.role_map")}</span>
                <textarea
                  class="textarea w-full font-mono"
                  rows="3"
                  bind:value={handing.roleMap}
                  placeholder="Acme Admins = owner"
                ></textarea>
                <p class="hint">{t("organization.signing_in.role_map_hint")}</p>
              </label>
              <div class="flex gap-2">
                <button type="button" class="btn btn-primary btn-sm" disabled={busy} onclick={handOver}>{t("organization.signing_in.save")}</button>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm"
                  onclick={() => (handing = idle())}
                >
                  {t("organization.signing_in.cancel")}
                </button>
              </div>
            </div>
          {/if}

          <div class="flex flex-col gap-2">
            <span class="legend">{t("organization.signing_in.domains")}</span>

            {#each organization.domains as claim (claim.domain)}
              <div class="flex flex-wrap items-center justify-between gap-2">
                <span class="font-mono text-sm break-all">{claim.domain}</span>
                <span class="hint">
                  {claim.verifiedAt
                    ? t("organization.signing_in.proven", { day: day(claim.verifiedAt) })
                    : t("organization.signing_in.waiting")} · {claim.provider?.name}
                </span>
              </div>
            {:else}
              <p class="hint">
                {t("organization.signing_in.no_domains")}
                <Link to="/domains" class="link">{t("organization.signing_in.domains_link")}</Link>
              </p>
            {/each}
          </div>

          <div class="flex flex-col gap-2">
            <span class="legend">{t("organization.signing_in.provisioning")}</span>
            <p class="hint">
              {organization.provisioningTokens.length
                ? t("organization.signing_in.tokens_reach", { count: organization.provisioningTokens.length })
                : t("organization.signing_in.no_tokens")}
              <Link to="/provisioning" class="link">{t("organization.signing_in.provisioning_link")}</Link>
            </p>
          </div>
        </Section>
      </div>

      <div class="flex flex-col gap-4">
        <Section title={t("organization.roles.title")} lede={t("organization.roles.lede")}>
          <div class="flex flex-wrap gap-2">
            {#each organization.roles as held (held)}
              <span class="badge badge-lg gap-1.5 {BUILT_IN.includes(held) ? 'badge-ghost' : 'badge-outline'}">
                <span class="font-medium">{held}</span>
                <span class="opacity-70">{holding[held] ?? 0}</span>
                {#if !BUILT_IN.includes(held)}
                  <button
                    type="button"
                    class="-mr-1 cursor-pointer px-1 opacity-70 hover:opacity-100 disabled:cursor-not-allowed disabled:opacity-30"
                    aria-label={t("organization.roles.stop_offering", { role: held })}
                    title={holding[held]
                      ? t("organization.roles.held", { count: holding[held] })
                      : t("organization.roles.stop_offering", { role: held })}
                    disabled={busy || holding[held] > 0}
                    onclick={() => dropRole(held)}
                  >
                    ×
                  </button>
                {/if}
              </span>
            {/each}
          </div>
          <Field
            label={t("organization.roles.offer")}
            bind:value={role}
            placeholder="support"
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
            onsave={addRole}
            save={t("organization.roles.add")}
          />
          <p class="hint">{t("organization.roles.hint")}</p>
        </Section>

        <Section title={t("organization.details.title")}>
          <Field label={t("organization.details.name")} bind:value={naming} onsave={rename} />
          <Facts rows={facts} />
        </Section>
      </div>
    </div>

    <Section title={t("organization.activity.title")} lede={t("organization.activity.lede")}>
      <Events events={organization.events} empty={t("organization.activity.empty")} />
    </Section>

    {#if !organization.archivedAt}
      <Section
        title={t("organization.archive.title")}
        lede={revoking("organization.archive.lede", "organization.archive.lede_tokens")}
      >
        <button type="button" class="btn btn-sm btn-error btn-outline self-start" disabled={busy} onclick={archive}>
          {t("organization.archive.button", { organization: organization.name })}
        </button>
      </Section>
    {/if}
  {/if}
</Page>

{#snippet roleOf(member)}
  <Select
    value={member.role}
    options={roleOptions}
    name={t("organization.members.role_of", { name: named(member) })}
    disabled={busy || lastOwner(member) || Boolean(organization.archivedAt)}
    onchange={(chosen) => setRole(member, chosen)}
  />
{/snippet}

{#snippet removeOf(member)}
  {#if member.pending}
    <button
      type="button"
      class="btn btn-ghost btn-sm"
      disabled={busy || Boolean(organization.archivedAt)}
      onclick={() => resend(member)}
    >
      {t("organization.members.send_again")}
    </button>
  {/if}
  <button
    type="button"
    class="btn btn-ghost btn-sm btn-error"
    disabled={busy || lastOwner(member)}
    title={lastOwner(member) ? t("organization.members.owner_first") : null}
    onclick={() => remove(member)}
  >
    {member.pending ? t("organization.members.withdraw") : t("organization.members.remove")}
  </button>
{/snippet}
