<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api } = $props();

  const QUERY = `
    query Groups {
      groups { key name memberCount members { uuid identifier } }
    }
  `;

  const feedback = createFeedback();

  let data = $state(null);
  let loading = $state(true);
  let key = $state("");
  let name = $state("");

  async function load() {
    loading = true;

    try {
      data = await api.query(QUERY);
    } catch (thrown) {
      feedback.blame(thrown);
    } finally {
      loading = false;
    }
  }

  load();

  async function create() {
    const done = await feedback.attempt(
      () =>
        api.query(
          `mutation Create($key: String!, $name: String!) { createGroup(key: $key, name: $name) { group { key } } }`,
          { key: key.trim(), name: name.trim() || key.trim() },
        ),
      `${name.trim() || key.trim()} is ready. Add people from their own pages.`,
    );

    if (!done) return;

    key = "";
    name = "";
    await load();
  }

  async function remove(group) {
    if (!confirm(`Delete ${group.name}? Apps limited to it turn its people away.`)) return;

    const done = await feedback.attempt(
      () => api.query(`mutation Delete($key: String!) { deleteGroup(key: $key) { key } }`, { key: group.key }),
      `${group.name} is deleted.`,
    );

    if (done) await load();
  }

  async function leave(group, actor) {
    const done = await feedback.attempt(
      () =>
        api.query(
          `mutation Leave($key: String!, $uuid: ID!) { removeGroupMember(key: $key, uuid: $uuid) { group { key } } }`,
          { key: group.key, uuid: actor.uuid },
        ),
      `${actor.identifier} is out of ${group.name}.`,
    );

    if (done) await load();
  }
</script>

<Page
  title="Groups"
  lede="Named sets of people, such as admins or family. Apps that ask for the groups scope see each group a person is in, and an app can be limited to some groups."
>
  <Notices feedback={feedback.state} />

  {#if loading && !data}
    <Spinner />
  {:else if data}
    <div class="grid gap-4">
      <Section
        row
        title="Add a group"
        help="The key is what apps see in the groups claim, so pick the one an app's role mapping expects, such as admins. It cannot change later."
      >
        <Field label="Key" bind:value={key} placeholder="admins" />
        <Field label="Name" bind:value={name} placeholder="Admins" />

        <button type="button" class="btn btn-primary btn-sm self-start" disabled={!key.trim()} onclick={create}>
          Add group
        </button>
      </Section>

      <Section row title="Groups">
        {#if data.groups.length === 0}
          <p class="text-sm opacity-85">No groups yet.</p>
        {:else}
          <ul class="flex flex-col divide-y divide-base-200">
            {#each data.groups as group (group.key)}
              <li class="flex flex-col gap-2 py-3">
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <div class="min-w-0">
                    <span class="text-sm font-medium">{group.name}</span>
                    <code class="hint ml-1 font-mono">{group.key}</code>
                    <span class="hint">· {group.memberCount} {group.memberCount === 1 ? "person" : "people"}</span>
                  </div>
                  <button type="button" class="btn btn-ghost btn-sm" onclick={() => remove(group)}>Delete</button>
                </div>

                {#if group.members.length}
                  <ul class="flex flex-wrap gap-2">
                    {#each group.members as actor (actor.uuid)}
                      <li class="badge badge-ghost gap-1">
                        <Link to={`/actors/${actor.uuid}`}>{actor.identifier}</Link>
                        <button
                          type="button"
                          class="opacity-70 hover:opacity-100"
                          aria-label={`Take ${actor.identifier} out of ${group.name}`}
                          onclick={() => leave(group, actor)}
                        >×</button>
                      </li>
                    {/each}
                  </ul>
                {/if}
              </li>
            {/each}
          </ul>
        {/if}
      </Section>
    </div>
  {/if}
</Page>
