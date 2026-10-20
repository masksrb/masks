<script>
  import { t } from "./lib/copy.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { since } from "./lib/format.js";
  import Notices from "./ui/Notices.svelte";
  import Section from "./ui/Section.svelte";
  import Select from "./ui/Select.svelte";

  let { api } = $props();

  const feedback = createFeedback();

  const SOURCES = ["manual", "rule", "provider", "group"];
  const KINDS = ["email_domain", "profile"];
  const FIELDS = ["name", "given_name", "family_name", "middle_name", "nickname", "gender", "zoneinfo", "locale"];

  const GROUPS = `query Groups {
    groups { key name memberCount source rule { kind field value } providerKey upstreamGroup parentLabels refreshedAt }
    providers { key name }
  }`;

  let groups = $state([]);
  let providers = $state([]);
  let name = $state("");
  let editing = $state(null);
  let draft = $state(null);
  let busy = $state(false);

  const key = $derived(
    name
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, ""),
  );

  const sourceOptions = SOURCES.map((source) => [source, t(`group_sources.sources.${source}`)]);
  const kindOptions = KINDS.map((kind) => [kind, t(`group_sources.kinds.${kind}`)]);
  const fieldOptions = FIELDS.map((field) => [field, t(`actor.fields.${field}`)]);
  const providerOptions = $derived([["", t("group_sources.choose_provider")], ...providers.map((held) => [held.key, held.name])]);

  async function load() {
    const answer = await feedback.attempt(() => api.query(GROUPS));

    if (!answer) return;

    groups = answer.groups;
    providers = answer.providers;
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

  function edit(group) {
    editing = group.key;
    draft = {
      source: group.source,
      rule: group.rule.length ? group.rule.map((held) => ({ ...held })) : [condition()],
      providerKey: group.providerKey ?? "",
      upstreamGroup: group.upstreamGroup ?? "",
      parents: group.parentLabels.join(", "),
    };
  }

  function condition() {
    return { kind: "email_domain", field: "name", value: "" };
  }

  function close() {
    editing = null;
    draft = null;
  }

  async function save(group) {
    busy = true;

    const variables = {
      key: group.key,
      source: draft.source,
      rule: draft.source === "rule" ? draft.rule.map(({ kind, field, value }) => ({ kind, field: kind === "profile" ? field : null, value })) : [],
      providerKey: draft.source === "provider" ? draft.providerKey : "",
      upstreamGroup: draft.source === "provider" ? draft.upstreamGroup : "",
      parentLabels: draft.source === "group" ? draft.parents.split(/[\s,]+/).filter(Boolean) : [],
    };

    const done = await feedback.attempt(
      () =>
        api.query(
          `mutation Fill($key: String!, $source: String!, $rule: [GroupConditionInput!]!, $providerKey: String!, $upstreamGroup: String!, $parentLabels: [String!]!) {
            updateGroup(key: $key, source: $source, rule: $rule, providerKey: $providerKey, upstreamGroup: $upstreamGroup, parentLabels: $parentLabels) { group { key } }
          }`,
          variables,
        ),
      t("group_sources.saved", { name: group.name, source: t(`group_sources.sources.${draft.source}`).toLowerCase() }),
    );

    busy = false;

    if (!done) return;

    close();
    await load();
  }

  async function refresh(group) {
    busy = true;

    const done = await feedback.attempt(
      () => api.query(`mutation Refresh($key: String!) { refreshGroup(key: $key) { group { key } } }`, { key: group.key }),
      t("group_sources.refreshed", { name: group.name }),
    );

    busy = false;

    if (done) await load();
  }

  function summary(group) {
    if (group.source === "provider") {
      const provider = providers.find((held) => held.key === group.providerKey);

      return t("group_sources.summary.provider", { provider: provider?.name ?? group.providerKey ?? "" });
    }

    if (group.source === "group") return t("group_sources.summary.group", { parents: group.parentLabels.join(", ") });

    return t("group_sources.summary.rule");
  }
</script>

<Section row title={t("groups.title")} help={t("groups.lede")}>
  <Notices feedback={feedback.state} />

  {#if groups.length}
    <ul class="compact-list">
      {#each groups as group (group.key)}
        <li class="flex-wrap">
          <span class="min-w-0 truncate text-sm font-medium">{group.name}</span>
          <code class="hint font-mono">{group.key}</code>
          <span class="hint">{t("groups.actors", { count: group.memberCount })}</span>
          {#if group.source !== "manual"}
            <span class="badge badge-ghost badge-sm">{summary(group)}</span>
          {/if}
          <span class="ml-auto flex items-center gap-1">
            {#if group.source !== "manual"}
              <button type="button" class="btn btn-ghost btn-xs" disabled={busy} onclick={() => refresh(group)}>
                {t("group_sources.refresh")}
              </button>
            {/if}
            <button
              type="button"
              class="btn btn-ghost btn-xs"
              aria-label={t("group_sources.change", { name: group.name })}
              onclick={() => (editing === group.key ? close() : edit(group))}
            >{t("group_sources.source")}</button>
            <button
              type="button"
              class="btn btn-ghost btn-xs"
              aria-label={t("groups.delete", { name: group.name })}
              onclick={() => remove(group)}
            >×</button>
          </span>

          {#if editing === group.key && draft}
            <form
              class="flex w-full flex-col gap-3 py-2"
              onsubmit={(event) => {
                event.preventDefault();
                save(group);
              }}
            >
              <Select
                label={t("group_sources.source")}
                value={draft.source}
                options={sourceOptions}
                disabled={busy}
                onchange={(source) => (draft.source = source)}
              />
              <p class="hint">{t(`group_sources.ledes.${draft.source}`)}</p>

              {#if draft.source === "rule"}
                {#each draft.rule as held, index (index)}
                  <div class="flex flex-wrap items-end gap-2">
                    <Select
                      name={t("group_sources.kinds.email_domain")}
                      value={held.kind}
                      options={kindOptions}
                      disabled={busy}
                      onchange={(kind) => (held.kind = kind)}
                    />
                    {#if held.kind === "profile"}
                      <Select
                        name={t("group_sources.field")}
                        value={held.field ?? "name"}
                        options={fieldOptions}
                        disabled={busy}
                        onchange={(field) => (held.field = field)}
                      />
                    {/if}
                    <input
                      class="input input-sm w-full max-w-60"
                      aria-label={t("group_sources.value")}
                      placeholder={held.kind === "email_domain" ? "example.com" : t("group_sources.value")}
                      bind:value={held.value}
                      disabled={busy}
                    />
                    {#if draft.rule.length > 1}
                      <button
                        type="button"
                        class="btn btn-ghost btn-xs"
                        aria-label={t("group_sources.remove_condition")}
                        disabled={busy}
                        onclick={() => draft.rule.splice(index, 1)}
                      >×</button>
                    {/if}
                  </div>
                {/each}
                {#if draft.rule.length < 5}
                  <button type="button" class="btn btn-ghost btn-xs w-fit" disabled={busy} onclick={() => draft.rule.push(condition())}>
                    {t("group_sources.add_condition")}
                  </button>
                {/if}
              {:else if draft.source === "provider"}
                {#if providers.length}
                  <Select
                    label={t("group_sources.provider")}
                    value={draft.providerKey}
                    options={providerOptions}
                    disabled={busy}
                    onchange={(held) => (draft.providerKey = held)}
                  />
                  <label class="flex flex-col gap-1.5">
                    <span class="field-label">{t("group_sources.upstream_group")}</span>
                    <input class="input input-sm w-full max-w-60" bind:value={draft.upstreamGroup} disabled={busy} />
                  </label>
                {:else}
                  <p class="hint">{t("group_sources.no_providers")}</p>
                {/if}
              {:else if draft.source === "group"}
                <label class="flex flex-col gap-1.5">
                  <span class="field-label">{t("group_sources.parent_labels")}</span>
                  <input class="input input-sm w-full max-w-100" bind:value={draft.parents} disabled={busy} />
                  <span class="hint">{t("group_sources.parent_labels_hint")}</span>
                </label>
              {/if}

              <div class="flex items-center gap-2">
                <button type="submit" class="btn btn-sm" disabled={busy}>{t("group_sources.save")}</button>
                <button type="button" class="btn btn-ghost btn-sm" disabled={busy} onclick={close}>{t("group_sources.cancel")}</button>
                {#if group.source !== "manual"}
                  <span class="hint">
                    {group.refreshedAt ? t("group_sources.refreshed_at", { when: since(group.refreshedAt) }) : t("group_sources.never_refreshed")}
                  </span>
                {/if}
              </div>
            </form>
          {/if}
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
