<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, plural, since } from "./lib/format.js";
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
    ["all", "Everyone"],
    ["owners", "Owners"],
    ["invited", "Invited"],
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

  const revoking = $derived(
    organization?.liveTokenCount ? ` and revokes its ${plural(organization.liveTokenCount, "live token")}` : "",
  );

  const counts = $derived(
    organization
      ? [
          { label: organization.memberCount === 1 ? "Member" : "Members", value: organization.memberCount },
          { label: organization.ownerCount === 1 ? "Owner" : "Owners", value: organization.ownerCount },
          { label: "Invitations open", value: organization.pendingCount },
          { label: "Live tokens", value: organization.liveTokenCount },
        ]
      : [],
  );

  const facts = $derived(
    organization
      ? [
          { term: "Key", value: organization.key, mono: true },
          { term: "ID", value: organization.uuid, mono: true },
          { term: "Asked for with", value: `organization=${organization.key}`, mono: true },
          { term: "Created", value: day(organization.createdAt) },
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
    if (member.expired) return `Expired ${since(member.expiresAt)}. Send it again to renew it.`;

    if (member.pending) {
      const by = member.invitedBy ? ` by ${member.invitedBy.identifier}` : "";

      return `Invited ${since(member.invitedAt)}${by}`;
    }

    return `${member.provisioned ? "From the directory, since" : "Since"} ${day(member.createdAt)}`;
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
      `${email} is invited as ${adding.role}. Nothing is granted until they accept.`,
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
      `${named(member)} is ${chosen} now. Their tokens under the old role stop working.`,
    );
  }

  function remove(member) {
    const question = member.pending
      ? `Withdraw the invitation to ${named(member)}?`
      : `Remove ${named(member)} from ${organization.name}? Their tokens for it stop working.`;

    if (!confirm(question)) return;

    run(
      `mutation Remove($organization: ID!, $uuid: ID!) {
        removeMember(organization: $organization, uuid: $uuid) { organization { key } }
      }`,
      { organization: organization.key, uuid: member.actor.uuid },
      member.pending ? `The invitation to ${named(member)} is withdrawn.` : `${named(member)} is out of ${organization.name}.`,
    );
  }

  function resend(member) {
    run(
      `mutation Resend($organization: ID!, $uuid: ID!) {
        resendOrganizationInvitation(organization: $organization, uuid: $uuid) { delivered }
      }`,
      { organization: organization.key, uuid: member.actor.uuid },
      `The invitation to ${named(member)} was sent again.`,
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

    if (await saveRoles([...custom, chosen], `${organization.name} offers ${chosen} now.`)) role = "";
  }

  function dropRole(held) {
    saveRoles(
      custom.filter((kept) => kept !== held),
      `${organization.name} no longer offers ${held}.`,
    );
  }

  function rename() {
    run(
      `mutation Rename($key: ID!, $name: String) {
        updateOrganization(key: $key, name: $name) { organization { key } }
      }`,
      { key: organization.key, name: naming.trim() },
      "Saved.",
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
      "Saved. People who sign in through it join this organization.",
    ).then((answer) => {
      if (answer) handing = idle();
    });
  }

  function handBack(provider) {
    if (!confirm(`Hand ${provider.name} back to the whole tenant? People who sign in through it stop joining ${organization.name}.`)) return;

    run(
      `mutation Back($key: ID!) { setProviderOrganization(key: $key, organization: null) { provider { key } } }`,
      { key: provider.key },
      `${provider.name} serves the whole tenant again.`,
    );
  }

  function setPolicy(key) {
    run(
      `mutation Policy($key: ID!, $policy: ID!) {
        updateOrganization(key: $key, signInPolicy: $policy) { organization { key } }
      }`,
      { key: organization.key, policy: key },
      "Saved.",
    );
  }

  async function archive() {
    if (!confirm(`Archive ${organization.name}? This stops anyone signing in as a member${revoking}.`)) return;

    await run(
      `mutation Archive($key: ID!) { archiveOrganization(key: $key) { organization { key } } }`,
      { key: organization.key },
      `${organization.name} is archived.`,
    );
  }

  function restore() {
    run(
      `mutation Restore($key: ID!) { restoreOrganization(key: $key) { organization { key } } }`,
      { key: organization.key },
      `${organization.name} is back.`,
    );
  }
</script>

<Page
  title={organization?.name ?? "Organization"}
  id={organization?.key}
  back={{ to: "/organizations", label: "Organizations" }}
  lede={organization
    ? organization.archivedAt
      ? `Archived ${since(organization.archivedAt)}. Nobody signs in as a member of it.`
      : `Apps name it with organization=${organization.key}, and tokens carry the member's role.`
    : null}
>
  <Notices feedback={feedback.state} />

  {#if loading && !organization}
    <Spinner />
  {:else if !organization}
    <p class="hint">No organization is keyed {organizationKey}. <Link to="/organizations">All organizations</Link></p>
  {:else}
    {#if organization.archivedAt}
      <div class="alert alert-warning alert-soft flex flex-wrap items-center justify-between gap-3" role="status">
        <span>Archived {day(organization.archivedAt)}. Members keep their roles, and restoring lets them sign in again.</span>
        <button type="button" class="btn btn-sm" disabled={busy} onclick={restore}>Restore</button>
      </div>
    {/if}

    {#if !organization.archivedAt && organization.ownerCount === 0}
      <div class="alert alert-warning alert-soft" role="status">
        Nobody owns {organization.name}, so only managers can change its members. Make a member an owner.
      </div>
    {/if}

    <Tally {counts} />

    {#if invited}
      <div class="alert alert-info alert-soft flex-col items-start gap-2" role="status">
        <span class="font-medium">No mail adapter is set up, so send this invitation link yourself. It works once.</span>
        <code class="font-mono text-xs break-all">{invited}</code>
      </div>
    {/if}

    <Section
      title="Members"
      lede="Owners manage members from their own account page too. An invitation grants nothing until it is accepted."
    >
      {#snippet actions()}
        <div class="range" role="group" aria-label="Who to show">
          {#each LENSES as [key, label] (key)}
            <button type="button" aria-pressed={lens === key} onclick={() => (lens = key)}>{label}</button>
          {/each}
        </div>
        {#if !organization.archivedAt}
          <button type="button" class="btn btn-primary btn-sm" onclick={openAdding}>Add member</button>
        {/if}
      {/snippet}

      {#if adding}
        <div class="grid gap-3 sm:grid-cols-[minmax(0,1fr)_10rem_auto] sm:items-end">
          <Field label="Email" type="email" bind:value={adding.email} placeholder="person@example.com" />
          <Select label="Role" value={adding.role} options={roleOptions} onchange={(chosen) => (adding.role = chosen)} />
          <div class="flex gap-2">
            <button type="button" class="btn btn-primary btn-sm" disabled={busy || !adding.email.trim()} onclick={add}>
              Invite
            </button>
            <button type="button" class="btn btn-ghost btn-sm" onclick={() => (adding = null)}>Cancel</button>
          </div>
        </div>
        <p class="hint">
          They join once they accept, from the address you invite. Someone without an account gets an invitation to make one.
        </p>
      {/if}

      <Table
        columns={["Person", { label: "Role", hide: true }, { label: "", right: true, hide: true }]}
        count={shown.length}
        empty={lens === "invited"
          ? "No invitations are open."
          : lens === "owners"
            ? "Nobody owns this organization. Make a member an owner so someone can manage it."
            : "Nobody belongs here yet. Add the first member as owner."}
      >
        {#snippet rows()}
          {#each shown as member (member.actor.uuid)}
            <tr>
              <td class="min-w-0">
                <div class="flex min-w-0 flex-col gap-0.5">
                  <span class="flex flex-wrap items-center gap-2">
                    <Link to={`/actors/${member.actor.uuid}`} class="link link-hover font-medium break-all">
                      {named(member)}
                    </Link>
                    {#if member.expired}<span class="badge badge-sm badge-error badge-soft">expired</span>
                    {:else if member.pending}<span class="badge badge-sm badge-warning badge-soft">invited</span>{/if}
                    {#if lastOwner(member)}<span class="badge badge-sm badge-ghost">last owner</span>{/if}
                  </span>
                  <span class="hint">{status(member)}</span>
                  <div class="mt-2 flex flex-wrap items-center gap-2 md:hidden">
                    <div class="min-w-28 flex-1 basis-28">{@render roleOf(member)}</div>
                    <div class="-me-3 flex shrink-0">{@render removeOf(member)}</div>
                  </div>
                </div>
              </td>
              <td class="hidden w-36 md:table-cell">
                {@render roleOf(member)}
              </td>
              <td class="hidden text-right md:table-cell">
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
          title="Signing in"
          lede="A member signs in under this policy, ahead of the app's and the tenant's. It applies from the first step when the app names the organization."
        >
          <Select
            label="Sign-in policy"
            value={organization.signInPolicy?.key ?? ""}
            options={[["", "The app's or the tenant's"], ...policies.map((policy) => [policy.key, policy.name])]}
            disabled={busy}
            onchange={setPolicy}
          />

          <div class="flex flex-col gap-2">
            <span class="legend">Providers</span>

            {#each organization.providers as provider (provider.key)}
              <div class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-base-300 p-3">
                <div class="flex min-w-0 flex-col">
                  <span class="font-medium">{provider.name}</span>
                  <span class="hint">
                    {Object.keys(provider.roleMap).length
                      ? Object.entries(provider.roleMap)
                          .map(([group, held]) => `${group} → ${held}`)
                          .join(", ")
                      : "No groups mapped"}. Anyone else joins as {provider.unmappedRole ?? "member"}.
                  </span>
                </div>
                <div class="flex gap-2">
                  <button type="button" class="btn btn-sm" disabled={busy} onclick={() => pickProvider(provider.key)}>Edit</button>
                  <button type="button" class="btn btn-ghost btn-sm" disabled={busy} onclick={() => handBack(provider)}>
                    Hand back
                  </button>
                </div>
              </div>
            {:else}
              <p class="hint">
                None. Give the organization its own provider, and everyone who signs in through it joins here in the role
                their groups map to.
              </p>
            {/each}

            {#if handable.length && !handing.provider}
              <Select
                value=""
                name="Give a provider to this organization"
                options={[
                  ["", "Give a provider to this organization"],
                  ...handable.map((provider) => [provider.key, provider.name]),
                ]}
                onchange={pickProvider}
              />
            {/if}
          </div>

          {#if handing.provider}
            <div class="flex flex-col gap-3 rounded-lg border border-base-300 p-3">
              <span class="font-medium">
                {providers.find((provider) => provider.key === handing.provider)?.name ?? handing.provider}
              </span>
              <div class="grid gap-3 sm:grid-cols-2">
                <Field label="Groups claim" bind:value={handing.roleClaim} placeholder="groups" />
                <Select
                  label="Role for anyone else"
                  value={handing.unmappedRole}
                  options={[["", "member"], ...roleOptions.filter(([held]) => held !== "member")]}
                  onchange={(chosen) => (handing.unmappedRole = chosen)}
                />
              </div>
              <label class="flex flex-col gap-1.5">
                <span class="field-label">Groups to roles</span>
                <textarea
                  class="textarea w-full font-mono"
                  rows="3"
                  bind:value={handing.roleMap}
                  placeholder="Acme Admins = owner"
                ></textarea>
                <p class="hint">One group per line. The first group a person holds decides their role, on every sign-in.</p>
              </label>
              <div class="flex gap-2">
                <button type="button" class="btn btn-primary btn-sm" disabled={busy} onclick={handOver}>Save</button>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm"
                  onclick={() => (handing = idle())}
                >
                  Cancel
                </button>
              </div>
            </div>
          {/if}

          <div class="flex flex-col gap-2">
            <span class="legend">Domains</span>

            {#each organization.domains as claim (claim.domain)}
              <div class="flex flex-wrap items-center justify-between gap-2">
                <span class="font-mono text-sm break-all">{claim.domain}</span>
                <span class="hint">
                  {claim.verifiedAt ? `Proven ${day(claim.verifiedAt)}` : "Waiting for its DNS record"} · {claim.provider?.name}
                </span>
              </div>
            {:else}
              <p class="hint">
                None proven. Until one of its providers proves a domain, owners can invite only the addresses sign-up
                admits, and a provisioning token cannot set email addresses.
                <Link to="/domains" class="link">Domains</Link>
              </p>
            {/each}
          </div>

          <div class="flex flex-col gap-2">
            <span class="legend">Provisioning</span>
            <p class="hint">
              {organization.provisioningTokens.length
                ? `${plural(organization.provisioningTokens.length, "live token reaches", "live tokens reach")} only this organization.`
                : "No provisioning token reaches only this organization."}
              <Link to="/provisioning" class="link">Provisioning</Link>
            </p>
          </div>
        </Section>
      </div>

      <div class="flex flex-col gap-4">
        <Section title="Roles" lede="A role is a word the member's tokens carry. Every organization offers owner and member.">
          <div class="flex flex-wrap gap-2">
            {#each organization.roles as held (held)}
              <span class="badge badge-lg gap-1.5 {BUILT_IN.includes(held) ? 'badge-ghost' : 'badge-outline'}">
                <span class="font-medium">{held}</span>
                <span class="opacity-70">{holding[held] ?? 0}</span>
                {#if !BUILT_IN.includes(held)}
                  <button
                    type="button"
                    class="-mr-1 cursor-pointer px-1 opacity-70 hover:opacity-100 disabled:cursor-not-allowed disabled:opacity-30"
                    aria-label={`Stop offering ${held}`}
                    title={holding[held] ? `${holding[held]} held, so it stays` : `Stop offering ${held}`}
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
            label="Offer another role"
            bind:value={role}
            placeholder="support"
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
            onsave={addRole}
            save="Add"
          />
          <p class="hint">Lowercase letters, digits, dashes, and underscores. A role someone holds stays until nobody does.</p>
        </Section>

        <Section title="Details">
          <Field label="Name" bind:value={naming} onsave={rename} />
          <Facts rows={facts} />
        </Section>
      </div>
    </div>

    <Section title="Activity" lede="Changes to the organization, and what happened while someone signed in as a member.">
      <Events events={organization.events} empty="Nothing yet." />
    </Section>

    {#if !organization.archivedAt}
      <Section
        title="Archive"
        lede={`Archiving stops anyone signing in as a member of ${organization.name}${revoking}. Members keep their roles, so restoring it puts everything back.`}
      >
        <button type="button" class="btn btn-sm btn-error btn-outline self-start" disabled={busy} onclick={archive}>
          Archive {organization.name}
        </button>
      </Section>
    {/if}
  {/if}
</Page>

{#snippet roleOf(member)}
  <Select
    value={member.role}
    options={roleOptions}
    name={`Role of ${named(member)}`}
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
      Send again
    </button>
  {/if}
  <button
    type="button"
    class="btn btn-ghost btn-sm"
    disabled={busy || lastOwner(member)}
    title={lastOwner(member) ? "Make someone else an owner first." : null}
    onclick={() => remove(member)}
  >
    {member.pending ? "Withdraw" : "Remove"}
  </button>
{/snippet}
