<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, plural } from "./lib/format.js";
  import OrganizationCell from "./OrganizationCell.svelte";
  import OrganizationHeadcount from "./OrganizationHeadcount.svelte";
  import { useRouter } from "./lib/router.svelte.js";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Row from "./ui/Row.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Table from "./ui/Table.svelte";

  let { api } = $props();

  const router = useRouter();
  const feedback = createFeedback();

  const QUERY = `
    query Organizations {
      active: organizations {
        key name roles memberCount ownerCount pendingCount
        signInPolicy { name }
        providers { name }
      }
      archived: organizations(archived: true) { key name memberCount archivedAt }
    }
  `;

  const COLUMNS = [
    "Organization",
    { label: "Members", hide: true },
    { label: "Roles", hide: true },
    { label: "Signs in with", hide: true },
  ];

  let data = $state(null);
  let loading = $state(true);
  let busy = $state(false);
  let draft = $state(null);
  let keyTouched = $state(false);

  async function load() {
    loading = true;

    const answer = await feedback.attempt(() => api.query(QUERY));

    loading = false;

    if (answer) data = answer;
  }

  load();

  const slug = (name) =>
    name
      .toLowerCase()
      .normalize("NFKD")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");

  function add() {
    draft = { key: "", name: "" };
    keyTouched = false;
    feedback.clear();
  }

  function named(name) {
    draft.name = name;
    if (!keyTouched) draft.key = slug(name);
  }

  async function save() {
    busy = true;

    const answer = await feedback.attempt(() =>
      api.query(
        `mutation Create($key: ID!, $name: String!) {
          createOrganization(key: $key, name: $name) { organization { key } }
        }`,
        { key: draft.key.trim(), name: draft.name.trim() },
      ),
    );

    busy = false;

    if (answer) router.go(`/organizations/${answer.createOrganization.organization.key}`);
  }

  async function restore(organization) {
    const done = await feedback.attempt(
      () =>
        api.query(`mutation Restore($key: ID!) { restoreOrganization(key: $key) { organization { key } } }`, {
          key: organization.key,
        }),
      `${organization.name} is back.`,
    );

    if (done) await load();
  }

  function members(organization) {
    const held = plural(organization.memberCount, "member");

    return organization.pendingCount ? `${held}, ${organization.pendingCount} invited` : held;
  }

  function signsIn(organization) {
    return [organization.signInPolicy?.name, ...organization.providers.map((provider) => provider.name)]
      .filter(Boolean)
      .join(", ");
  }
</script>

<Page
  title="Organizations"
  lede="The customers inside this tenant. An app that asks for the organization scope signs a person in as a member of one, and their token carries the role they hold there."
>
  {#snippet actions()}
    <button type="button" class="btn btn-primary btn-sm" onclick={add}>Add organization</button>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if draft}
    <Section title="Add organization" lede="You become its first owner, and can add members once it exists.">
      <div class="grid gap-3 sm:grid-cols-2">
        <Field label="Name" value={draft.name} oninput={(event) => named(event.currentTarget.value)} placeholder="Acme" />
        <Field
          label="Key"
          bind:value={draft.key}
          oninput={() => (keyTouched = true)}
          placeholder="acme"
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
        />
      </div>
      <p class="hint">
        An app asks for this organization with <span class="font-mono">organization={draft.key || "key"}</span>. The key
        cannot change later.
      </p>
      <div class="flex gap-2">
        <button
          type="button"
          class="btn btn-primary btn-sm"
          disabled={busy || !draft.key.trim() || !draft.name.trim()}
          onclick={save}
        >
          {busy ? "Adding..." : "Add organization"}
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onclick={() => (draft = null)}>Cancel</button>
      </div>
    </Section>
  {/if}

  {#if loading && !data}
    <Spinner />
  {:else if data}
    <Table
      columns={COLUMNS}
      count={data.active.length}
      empty="No organizations yet. Add one for each customer whose people sign in together."
    >
      {#snippet rows()}
        {#each data.active as organization (organization.key)}
          <Row to={`/organizations/${organization.key}`}>
            <td>
              <div class="flex min-w-0 flex-col gap-0.5">
                <OrganizationCell {organization}>
                  <span class="text-xs opacity-85 md:hidden">{members(organization)}</span>
                </OrganizationCell>
              </div>
            </td>
            <td class="hidden text-sm md:table-cell">
              <OrganizationHeadcount {organization} />
            </td>
            <td class="hidden md:table-cell">
              <div class="flex max-w-64 flex-wrap gap-1">
                {#each organization.roles as role (role)}
                  <span class="badge badge-ghost badge-sm">{role}</span>
                {/each}
              </div>
            </td>
            <td class="hidden text-sm md:table-cell">
              <span class:opacity-60={!signsIn(organization)}>{signsIn(organization) || "The tenant's policy"}</span>
            </td>
          </Row>
        {/each}
      {/snippet}
    </Table>

    {#if data.archived.length}
      <Section title="Archived" lede="Nobody signs in as a member of these. Restoring one puts its members back as they were.">
        {#each data.archived as organization (organization.key)}
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div class="flex min-w-0 flex-col">
              <Link to={`/organizations/${organization.key}`} class="link link-hover text-sm font-medium">
                {organization.name}
              </Link>
              <span class="hint">
                <span class="font-mono">{organization.key}</span> · archived {day(organization.archivedAt)} ·
                {plural(organization.memberCount, "member")}
              </span>
            </div>
            <button type="button" class="btn btn-ghost btn-sm" onclick={() => restore(organization)}>Restore</button>
          </div>
        {/each}
      </Section>
    {/if}
  {/if}
</Page>
