<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { useRouter } from "./lib/router.svelte.js";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api } = $props();

  const router = useRouter();
  const feedback = createFeedback();

  const QUERY = `
    query Organizations {
      active: organizations { key name memberCount roles }
      archived: organizations(archived: true) { key name memberCount }
    }
  `;

  let data = $state(null);
  let loading = $state(true);
  let busy = $state(false);
  let draft = $state(null);

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

  let keyTouched = $state(false);

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
</script>

<Page title="Organizations">
  <Notices feedback={feedback.state} />

  {#if loading && !data}
    <Spinner />
  {:else if data}
    {#if draft}
      <Section title="Add organization">
        <div class="grid gap-3 sm:grid-cols-2">
          <Field label="Name" value={draft.name} oninput={(event) => named(event.currentTarget.value)} />
          <Field
            label="Key"
            bind:value={draft.key}
            oninput={() => (keyTouched = true)}
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
          />
        </div>
        <p class="hint">
          An app asks for this organization with <span class="font-mono">organization={draft.key || "key"}</span>.
        </p>
        <div class="flex gap-2">
          <button
            type="button"
            class="btn btn-primary btn-sm"
            disabled={busy || !draft.key.trim() || !draft.name.trim()}
            onclick={save}
          >
            Add
          </button>
          <button type="button" class="btn btn-ghost btn-sm" onclick={() => (draft = null)}>Cancel</button>
        </div>
      </Section>
    {/if}

    <Section
      title="Organizations"
      lede={data.active.length
        ? "The customers inside this tenant. An app that asks for the organization scope signs a person in as a member of one."
        : "None yet. Add one for each customer whose people sign in together."}
    >
      {#snippet actions()}
        <button type="button" class="btn btn-sm" onclick={add}>Add</button>
      {/snippet}

      {#each data.active as organization (organization.key)}
        <div class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-base-300 p-3">
          <div class="flex min-w-0 flex-col">
            <Link to={`/organizations/${organization.key}`} class="link link-hover font-medium">
              {organization.name}
            </Link>
            <span class="hint">
              <span class="font-mono">{organization.key}</span> ·
              {organization.memberCount}
              {organization.memberCount === 1 ? "member" : "members"} · {organization.roles.join(", ")}
            </span>
          </div>
        </div>
      {/each}
    </Section>

    {#if data.archived.length}
      <Section title="Archived">
        {#each data.archived as organization (organization.key)}
          <div class="flex flex-wrap items-center justify-between gap-2">
            <span class="text-sm">{organization.name} <span class="hint font-mono">{organization.key}</span></span>
            <button type="button" class="btn btn-ghost btn-sm" onclick={() => restore(organization)}>Restore</button>
          </div>
        {/each}
      </Section>
    {/if}
  {/if}
</Page>
