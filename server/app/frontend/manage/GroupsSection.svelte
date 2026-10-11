<script>
  import { t } from "./lib/copy.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import Notices from "./ui/Notices.svelte";
  import Section from "./ui/Section.svelte";

  let { api } = $props();

  const feedback = createFeedback();

  let groups = $state([]);
  let name = $state("");

  const key = $derived(
    name
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, ""),
  );

  async function load() {
    const answer = await feedback.attempt(() => api.query(`query Groups { groups { key name memberCount } }`));

    if (answer) groups = answer.groups;
  }

  load();

  async function create() {
    if (!key) return;

    const label = name.trim();
    const done = await feedback.attempt(
      () =>
        api.query(`mutation Create($key: String!, $name: String!) { createGroup(key: $key, name: $name) { group { key } } }`, {
          key,
          name: label,
        }),
      t("groups.added", { name: label }),
    );

    if (!done) return;

    name = "";
    await load();
  }

  async function remove(group) {
    if (!confirm(t("groups.delete_confirm", { name: group.name }))) return;

    const done = await feedback.attempt(
      () => api.query(`mutation Delete($key: String!) { deleteGroup(key: $key) { key } }`, { key: group.key }),
      t("groups.deleted", { name: group.name }),
    );

    if (done) await load();
  }
</script>

<Section row title={t("groups.title")} help={t("groups.lede")}>
  <Notices feedback={feedback.state} />

  {#if groups.length}
    <ul class="compact-list">
      {#each groups as group (group.key)}
        <li>
          <span class="min-w-0 truncate text-sm font-medium">{group.name}</span>
          <code class="hint font-mono">{group.key}</code>
          <span class="hint">{t("groups.people", { count: group.memberCount })}</span>
          <button
            type="button"
            class="btn btn-ghost btn-xs ml-auto"
            aria-label={t("groups.delete", { name: group.name })}
            onclick={() => remove(group)}
          >×</button>
        </li>
      {/each}
    </ul>
  {/if}

  <form
    class="join"
    onsubmit={(event) => {
      event.preventDefault();
      create();
    }}
  >
    <input class="input input-sm join-item w-full max-w-60" aria-label={t("groups.new")} placeholder={t("groups.new")} bind:value={name} />
    <button type="submit" class="btn btn-sm join-item" disabled={!key}>{t("groups.add")}</button>
  </form>

  {#if key}
    <p class="hint">{t("groups.key", { key })}</p>
  {/if}
</Section>
