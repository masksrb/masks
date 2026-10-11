<script>
  import { t } from "./lib/copy.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
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
    t("organizations.columns.organization"),
    { label: t("organizations.columns.members"), hide: true },
    { label: t("organizations.columns.roles"), hide: true },
    { label: t("organizations.columns.signs_in"), hide: true },
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
      t("organizations.restored", { name: organization.name }),
    );

    if (done) await load();
  }

  function members(organization) {
    const held = t("organizations.members", { count: organization.memberCount });

    return organization.pendingCount
      ? t("organizations.members_invited", { members: held, count: organization.pendingCount })
      : held;
  }

  function signsIn(organization) {
    return [organization.signInPolicy?.name, ...organization.providers.map((provider) => provider.name)]
      .filter(Boolean)
      .join(", ");
  }
</script>

<Page
  title={t("organizations.title")}
  lede={t("organizations.lede")}
>
  {#snippet actions()}
    <button type="button" class="btn btn-primary btn-sm" onclick={add}>{t("organizations.add")}</button>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if draft}
    <Section title={t("organizations.add")} lede={t("organizations.add_lede")}>
      <div class="grid gap-3 sm:grid-cols-2">
        <Field label={t("organizations.name")} value={draft.name} oninput={(event) => named(event.currentTarget.value)} placeholder="Acme" />
        <Field
          label={t("organizations.key")}
          bind:value={draft.key}
          oninput={() => (keyTouched = true)}
          placeholder="acme"
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
        />
      </div>
      <p class="hint">
        {t("organizations.key_hint")}
        <span class="font-mono">organization={draft.key || t("organizations.key_word")}</span>{t("organizations.key_hint_end")}
      </p>
      <div class="flex gap-2">
        <button
          type="button"
          class="btn btn-primary btn-sm"
          disabled={busy || !draft.key.trim() || !draft.name.trim()}
          onclick={save}
        >
          {busy ? t("organizations.adding") : t("organizations.add")}
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onclick={() => (draft = null)}>{t("organizations.cancel")}</button>
      </div>
    </Section>
  {/if}

  {#if loading && !data}
    <Spinner />
  {:else if data}
    <Table
      columns={COLUMNS}
      count={data.active.length}
      empty={t("organizations.empty")}
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
              <span class:opacity-60={!signsIn(organization)}>{signsIn(organization) || t("organizations.tenant_policy")}</span>
            </td>
          </Row>
        {/each}
      {/snippet}
    </Table>

    {#if data.archived.length}
      <Section title={t("organizations.archived.title")} lede={t("organizations.archived.lede")}>
        {#each data.archived as organization (organization.key)}
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div class="flex min-w-0 flex-col">
              <Link to={`/organizations/${organization.key}`} class="link link-hover text-sm font-medium">
                {organization.name}
              </Link>
              <span class="hint">
                <span class="font-mono">{organization.key}</span>
                {t("organizations.archived.detail", {
                  day: day(organization.archivedAt),
                  members: t("organizations.members", { count: organization.memberCount }),
                })}
              </span>
            </div>
            <button type="button" class="btn btn-ghost btn-sm" onclick={() => restore(organization)}>{t("organizations.restore")}</button>
          </div>
        {/each}
      </Section>
    {/if}
  {/if}
</Page>
