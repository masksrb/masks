<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import { useRouter } from "./lib/router.svelte.js";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
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
        members { role createdAt actor { uuid identifier email activated } }
      }
    }
  `;

  let organization = $state(null);
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
        addMember(organization: $organization, email: $email, role: $role) { invited delivered url }
      }`,
      { organization: organization.key, email, role: adding.role },
      `${email} is a member now.`,
    );

    if (!answer) return;

    adding = { email: "", role: "member" };

    if (answer.addMember.invited && !answer.addMember.delivered) invited = answer.addMember.url;
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
              {member.actor.activated ? `since ${day(member.createdAt)}` : "invited, not signed in yet"}
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
      <p class="hint">Someone without an account gets an invitation.</p>

      {#if invited}
        <Field label="No mail adapter, so send this invitation link yourself" value={invited} readonly />
      {/if}
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
