<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { t } from "./lib/copy.js";
  import { day } from "./lib/format.js";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Select from "./ui/Select.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api } = $props();

  const FIELDS = `key name url actions lastDeliveredAt lastFailure archivedAt createdAt organization { key name }`;

  const QUERY = `
    query Streams {
      active: eventStreams { ${FIELDS} }
      archived: eventStreams(archived: true) { ${FIELDS} }
      organizations { key name }
    }
  `;

  const feedback = createFeedback();

  let data = $state(null);
  let loading = $state(true);
  let busy = $state(false);
  let editing = $state(null);
  let draft = $state(null);
  let secret = $state(null);

  async function load() {
    loading = true;

    const answer = await feedback.attempt(() => api.query(QUERY));

    loading = false;

    if (answer) data = answer;
  }

  load();

  const listed = (text) =>
    text
      .split(/[\s,]+/)
      .map((held) => held.trim())
      .filter(Boolean);

  function add() {
    editing = "";
    draft = { key: "", name: "", url: "", actions: "", organization: "" };
    secret = null;
    feedback.clear();
  }

  function edit(stream) {
    editing = stream.key;
    draft = {
      key: stream.key,
      name: stream.name,
      url: stream.url,
      actions: stream.actions.join("\n"),
      organization: stream.organization?.key ?? "",
    };
    secret = null;
    feedback.clear();
  }

  function close() {
    editing = null;
    draft = null;
    feedback.clear();
  }

  async function save() {
    busy = true;

    const fresh = editing === "";
    const variables = {
      key: draft.key.trim(),
      name: draft.name.trim(),
      url: draft.url.trim(),
      actions: listed(draft.actions),
      organization: draft.organization,
    };

    const answer = await feedback.attempt(
      () =>
        fresh
          ? api.query(
              `mutation Create($key: ID!, $name: String!, $url: String!, $actions: [String!], $organization: ID) {
                createEventStream(key: $key, name: $name, url: $url, actions: $actions, organization: $organization) { secret }
              }`,
              variables,
            )
          : api.query(
              `mutation Update($key: ID!, $name: String, $url: String, $actions: [String!], $organization: ID) {
                updateEventStream(key: $key, name: $name, url: $url, actions: $actions, organization: $organization) {
                  eventStream { key }
                }
              }`,
              variables,
            ),
      fresh ? t("streams.added", { name: draft.name }) : t("streams.saved", { name: draft.name }),
    );

    busy = false;

    if (!answer) return;

    secret = fresh ? answer.createEventStream.secret : null;

    close();
    await load();
  }

  async function act(mutation, stream, notice, question = null) {
    if (question && !confirm(question)) return;

    const done = await feedback.attempt(
      () =>
        api.query(`mutation Act($key: ID!) { ${mutation}(key: $key) { eventStream { key } } }`, {
          key: stream.key,
        }),
      notice,
    );

    if (done) await load();
  }

  async function rotate(stream) {
    if (!confirm(t("streams.rotate_confirm", { name: stream.name }))) return;

    const answer = await feedback.attempt(() =>
      api.query(`mutation Rotate($key: ID!) { rotateEventStreamSecret(key: $key) { secret } }`, {
        key: stream.key,
      }),
    );

    if (answer) secret = answer.rotateEventStreamSecret.secret;
  }

  async function test(stream) {
    busy = true;

    const answer = await feedback.attempt(() =>
      api.query(`mutation Test($key: ID!) { testEventStream(key: $key) { delivered failure } }`, {
        key: stream.key,
      }),
    );

    busy = false;

    if (!answer) return;

    if (answer.testEventStream.delivered) {
      feedback.say(t("streams.tested", { name: stream.name }));
    } else {
      feedback.blame(answer.testEventStream.failure);
    }

    await load();
  }

  const complete = $derived(draft?.key.trim() && draft.name.trim() && draft.url.trim());
</script>

<Page title={t("streams.title")}>
  <Notices feedback={feedback.state} />

  {#if loading && !data}
    <Spinner />
  {:else if data}
    {#if secret}
      <Section
        title={t("streams.secret.title")}
        lede={t("streams.secret.lede")}
      >
        <input class="input input-sm w-full font-mono" readonly value={secret} onfocus={(event) => event.currentTarget.select()} />
        <div>
          <button type="button" class="btn btn-ghost btn-sm" onclick={() => (secret = null)}>{t("streams.secret.saved")}</button>
        </div>
      </Section>
    {/if}

    {#if draft}
      <Section title={editing === "" ? t("streams.form.add") : t("streams.form.edit", { name: draft.name })}>
        <div class="grid gap-3 sm:grid-cols-2">
          <Field
            label={t("streams.form.key")}
            bind:value={draft.key}
            disabled={editing !== ""}
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
          />
          <Field label={t("streams.form.name")} bind:value={draft.name} />
        </div>

        <Field
          label={t("streams.form.address")}
          type="url"
          bind:value={draft.url}
          placeholder="https://siem.example.com/masks"
          autocapitalize="none"
          spellcheck="false"
        />

        <label class="flex flex-col gap-1.5">
          <span class="field-label">{t("streams.form.actions")}</span>
          <textarea
            class="textarea w-full font-mono"
            rows="4"
            bind:value={draft.actions}
            placeholder="session.started&#10;actor.deleted"
          ></textarea>
          <p class="hint">{t("streams.form.actions_hint")}</p>
        </label>

        {#if data.organizations.length}
          <Select
            label={t("streams.form.events_from")}
            value={draft.organization}
            options={[["", t("streams.form.every_organization")], ...data.organizations.map((held) => [held.key, t("streams.form.only", { name: held.name })])]}
            onchange={(key) => (draft.organization = key)}
          />
        {/if}

        <div class="flex gap-2">
          <button type="button" class="btn btn-primary btn-sm" disabled={busy || !complete} onclick={save}>
            {editing === "" ? t("streams.form.create") : t("streams.form.save")}
          </button>
          <button type="button" class="btn btn-ghost btn-sm" onclick={close}>{t("streams.form.cancel")}</button>
        </div>
      </Section>
    {/if}

    <Section
      title={t("streams.list.title")}
      lede={data.active.length ? t("streams.list.lede") : t("streams.list.empty")}
    >
      {#snippet actions()}
        <button type="button" class="btn btn-sm" onclick={add}>{t("streams.list.add")}</button>
      {/snippet}

      {#each data.active as stream (stream.key)}
        <div class="flex flex-col gap-3 sheet p-3">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div class="flex min-w-0 flex-col">
              <span class="font-medium">{stream.name}</span>
              <span class="hint break-all">
                <span class="font-mono">{stream.key}</span> · {stream.url} · {t("streams.list.added", { day: day(stream.createdAt) })}
              </span>
              <span class="hint">
                {stream.actions.length ? stream.actions.join(", ") : t("streams.list.every_action")}{stream.organization
                  ? t("streams.list.only", { name: stream.organization.name })
                  : ""}
              </span>
              {#if stream.lastFailure}
                <span class="text-sm text-error">{stream.lastFailure}</span>
              {:else if stream.lastDeliveredAt}
                <span class="hint">{t("streams.list.last_delivered", { day: day(stream.lastDeliveredAt) })}</span>
              {/if}
            </div>

            <div class="flex flex-wrap gap-2">
              <button type="button" class="btn btn-sm" disabled={busy} onclick={() => test(stream)}>{t("streams.list.test")}</button>
              <button type="button" class="btn btn-sm" onclick={() => edit(stream)}>{t("streams.list.edit")}</button>
              <button type="button" class="btn btn-ghost btn-sm" onclick={() => rotate(stream)}>{t("streams.list.rotate")}</button>
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                onclick={() =>
                  act(
                    "archiveEventStream",
                    stream,
                    t("streams.archived_notice", { name: stream.name }),
                    t("streams.archive_confirm", { name: stream.name }),
                  )}
              >
                {t("streams.list.archive")}
              </button>
            </div>
          </div>
        </div>
      {/each}
    </Section>

    {#if data.archived.length}
      <Section title={t("streams.archived.title")}>
        {#each data.archived as stream (stream.key)}
          <div class="flex flex-wrap items-center justify-between gap-2">
            <span class="text-sm">{stream.name} <span class="hint">{stream.url}</span></span>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              onclick={() => act("restoreEventStream", stream, t("streams.restored", { name: stream.name }))}
            >
              {t("streams.archived.restore")}
            </button>
          </div>
        {/each}
      </Section>
    {/if}
  {/if}
</Page>
