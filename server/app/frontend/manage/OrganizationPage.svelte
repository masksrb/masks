<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import { useRouter } from "./lib/router.svelte.js";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
  import Events from "./Events.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Select from "./ui/Select.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api, organizationKey } = $props();

  const router = useRouter();
  const feedback = createFeedback();

  const QUERY = `
    query Organization($key: ID!) {
      organization(key: $key) {
        uuid key name roles archivedAt createdAt
        signInPolicy { key }
        providers { key name roleClaim roleMap unmappedRole }
        members { role pending createdAt actor { uuid identifier email activated } }
        events {
          id action label createdAt ipAddress details
          actor { uuid identifier } by { uuid identifier } client { clientId name } device { id label }
        }
      }
      signInPolicies { key name }
      providers { key name organization { key } }
    }
  `;

  let organization = $state(null);
  let policies = $state([]);
  let providers = $state([]);
  let handing = $state({ provider: "", roleClaim: "", roleMap: "", unmappedRole: "" });
  let loading = $state(true);
  let busy = $state(false);
  let adding = $state({ email: "", role: "member" });
  let naming = $state({ name: "", roles: "" });
  let invited = $state(null);

  async function load() {
    loading = true;

    const answer = await feedback.attempt(() => api.query(QUERY, { key: organizationKey }));

    loading = false;

    if (!answer) return;

    organization = answer.organization;
    policies = answer.signInPolicies;
    providers = answer.providers;

    if (organization) {
      naming = {
        name: organization.name,
        roles: organization.roles.filter((role) => role !== "owner" && role !== "member").join(" "),
      };
    }
  }

  load();

  const roleOptions = $derived((organization?.roles ?? []).map((role) => [role, role]));

  async function run(query, variables, notice) {
    busy = true;

    const answer = await feedback.attempt(() => api.query(query, variables), notice);

    busy = false;

    if (answer) await load();

    return answer;
  }

  async function add() {
    const email = adding.email.trim();

    invited = null;

    const answer = await run(
      `mutation Add($organization: ID!, $email: String!, $role: String!) {
        addMember(organization: $organization, email: $email, role: $role) { delivered url }
      }`,
      { organization: organization.key, email, role: adding.role },
      `${email} is a member now.`,
    );

    if (!answer) return;

    adding = { email: "", role: "member" };

    if (!answer.addMember.delivered) invited = answer.addMember.url;
  }

  function setRole(member, role) {
    run(
      `mutation Role($organization: ID!, $uuid: ID!, $role: String!) {
        setMemberRole(organization: $organization, uuid: $uuid, role: $role) { membership { role } }
      }`,
      { organization: organization.key, uuid: member.actor.uuid, role },
      `${member.actor.identifier} is ${role} now.`,
    );
  }

  function remove(member) {
    if (!confirm(`Remove ${member.actor.identifier} from ${organization.name}? Their tokens for it stop working.`)) return;

    run(
      `mutation Remove($organization: ID!, $uuid: ID!) {
        removeMember(organization: $organization, uuid: $uuid) { organization { key } }
      }`,
      { organization: organization.key, uuid: member.actor.uuid },
      `${member.actor.identifier} is out of ${organization.name}.`,
    );
  }

  function rename() {
    run(
      `mutation Update($key: ID!, $name: String, $roles: [String!]) {
        updateOrganization(key: $key, name: $name, roles: $roles) { organization { key } }
      }`,
      {
        key: organization.key,
        name: naming.name.trim(),
        roles: naming.roles.split(/[\s,]+/).filter(Boolean),
      },
      "Saved.",
    );
  }

  const lines = (map) =>
    Object.entries(map ?? {})
      .map(([group, role]) => `${group} = ${role}`)
      .join("\n");

  const parsed = (text) =>
    Object.fromEntries(
      text
        .split("\n")
        .map((line) => line.split("="))
        .filter((parts) => parts.length === 2 && parts[0].trim() && parts[1].trim())
        .map(([group, role]) => [group.trim(), role.trim()]),
    );

  const handable = $derived(
    providers.filter((provider) => !provider.organization || provider.organization.key === organization?.key),
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
    );
  }

  function handBack(provider) {
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
    if (!confirm(`Archive ${organization.name}? Nobody signs in as a member of it, and its tokens stop working.`)) return;

    const answer = await run(
      `mutation Archive($key: ID!) { archiveOrganization(key: $key) { organization { key } } }`,
      { key: organization.key },
      `${organization.name} is archived.`,
    );

    if (answer) router.go("/organizations");
  }
</script>

<Page title={organization?.name ?? "Organization"}>
  <Notices feedback={feedback.state} />

  {#if loading && !organization}
    <Spinner />
  {:else if !organization}
    <p class="hint">No organization is keyed {organizationKey}. <Link to="/organizations">All organizations</Link></p>
  {:else}
    <Section
      title="Members"
      lede="Tokens for an app that asks for the organization scope carry the member's role here."
    >
      {#each organization.members as member (member.actor.uuid)}
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex min-w-0 flex-col">
            <Link to={`/actors/${member.actor.uuid}`} class="link link-hover font-medium">
              {member.actor.identifier}
            </Link>
            <span class="hint">
              {member.pending ? "invited, has not accepted yet" : `since ${day(member.createdAt)}`}
            </span>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <div class="w-36">
              <Select value={member.role} options={roleOptions} disabled={busy} onchange={(role) => setRole(member, role)} />
            </div>
            <button type="button" class="btn btn-ghost btn-sm" disabled={busy} onclick={() => remove(member)}>Remove</button>
          </div>
        </div>
      {:else}
        <p class="hint">Nobody yet. Add the first member as owner.</p>
      {/each}

      <div class="grid gap-3 sm:grid-cols-[1fr_10rem_auto] sm:items-end">
        <Field label="Add by email" type="email" bind:value={adding.email} placeholder="person@example.com" />
        <Select label="Role" value={adding.role} options={roleOptions} onchange={(role) => (adding.role = role)} />
        <button type="button" class="btn btn-sm" disabled={busy || !adding.email.trim()} onclick={add}>Add</button>
      </div>
      <p class="hint">They join once they accept on their account page. Someone without an account gets an invitation first.</p>

      {#if invited}
        <Field label="No mail adapter, so send this invitation link yourself" value={invited} readonly />
      {/if}
    </Section>

    <Section
      title="Signing in"
      lede="A member signs in under this policy, ahead of the app's and the tenant's. Name the organization on the request so its policy applies from the first step."
    >
      <Select
        label="Sign-in policy"
        value={organization.signInPolicy?.key ?? ""}
        options={[["", "The app's or the tenant's"], ...policies.map((policy) => [policy.key, policy.name])]}
        disabled={busy}
        onchange={setPolicy}
      />

      {#each organization.providers as provider (provider.key)}
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex min-w-0 flex-col">
            <span class="font-medium">{provider.name}</span>
            <span class="hint">
              {Object.keys(provider.roleMap).length
                ? Object.entries(provider.roleMap).map(([group, role]) => `${group} → ${role}`).join(", ")
                : "no groups mapped"}, otherwise {provider.unmappedRole ?? "member"}
            </span>
          </div>
          <div class="flex gap-2">
            <button type="button" class="btn btn-sm" disabled={busy} onclick={() => pickProvider(provider.key)}>Edit</button>
            <button type="button" class="btn btn-ghost btn-sm" disabled={busy} onclick={() => handBack(provider)}>Hand back</button>
          </div>
        </div>
      {/each}

      {#if handable.length}
        <Select
          label="Provider for this organization"
          value={handing.provider}
          options={[["", "Choose a provider"], ...handable.map((provider) => [provider.key, provider.name])]}
          onchange={pickProvider}
        />
      {/if}

      {#if handing.provider}
        <div class="grid gap-3 sm:grid-cols-2">
          <Field label="Groups claim" bind:value={handing.roleClaim} placeholder="groups" />
          <Select
            label="Role for anyone else"
            value={handing.unmappedRole}
            options={[["", "member"], ...roleOptions.filter(([role]) => role !== "member")]}
            onchange={(role) => (handing.unmappedRole = role)}
          />
        </div>
        <label class="flex flex-col gap-1.5">
          <span class="field-label">Groups to roles</span>
          <textarea class="textarea w-full font-mono" rows="3" bind:value={handing.roleMap} placeholder="Acme Admins = owner"></textarea>
          <p class="hint">One group per line. The first group a person holds decides their role, on every sign-in.</p>
        </label>
        <div class="flex gap-2">
          <button type="button" class="btn btn-sm" disabled={busy} onclick={handOver}>Save</button>
          <button type="button" class="btn btn-ghost btn-sm" onclick={() => (handing = { provider: "", roleClaim: "", roleMap: "", unmappedRole: "" })}>
            Cancel
          </button>
        </div>
      {/if}
    </Section>

    <Section title="Activity" lede="Events recorded while someone signed in as a member, and changes to the organization.">
      <Events events={organization.events} empty="Nothing yet." />
    </Section>

    <Section title="Details">
      <div class="grid gap-3 sm:grid-cols-2">
        <Field label="Name" bind:value={naming.name} />
        <Field label="Other roles" bind:value={naming.roles} placeholder="admin billing" />
      </div>
      <p class="hint">
        Every organization has owner and member. Key <span class="font-mono">{organization.key}</span>, id
        <span class="font-mono">{organization.uuid}</span>.
      </p>
      <div class="flex gap-2">
        <button type="button" class="btn btn-sm" disabled={busy || !naming.name.trim()} onclick={rename}>Save</button>
        <button type="button" class="btn btn-ghost btn-sm" disabled={busy} onclick={archive}>Archive</button>
      </div>
    </Section>
  {/if}
</Page>
