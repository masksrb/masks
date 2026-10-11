<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { t } from "./lib/copy.js";
  import { day } from "./lib/format.js";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Switch from "./ui/Switch.svelte";

  let { api } = $props();

  const FIELDS = `key name kind service label primary settings secretsHeld archivedAt createdAt`;

  const QUERY = `
    query Senders {
      active: senders { ${FIELDS} }
      archived: senders(archived: true) { ${FIELDS} }
      senderServices {
        service kind label
        fields { key label type secret required options default hint }
      }
      tenant { mails texts }
    }
  `;

  const KINDS = [
    {
      kind: "mail",
      title: t("senders.kinds.mail.title"),
      lede: t("senders.kinds.mail.lede"),
      idle: t("senders.kinds.mail.idle"),
      to: "you@example.com",
    },
    {
      kind: "sms",
      title: t("senders.kinds.sms.title"),
      lede: t("senders.kinds.sms.lede"),
      idle: t("senders.kinds.sms.idle"),
      to: "+15551234567",
    },
  ];

  const feedback = createFeedback();

  let data = $state(null);
  let loading = $state(true);
  let busy = $state(false);
  let editing = $state(null);
  let draft = $state(null);
  let testing = $state({});

  const services = $derived(data?.senderServices ?? []);
  const serviceOf = (name) => services.find((held) => held.service === name);
  const forKind = (list, kind) => (list ?? []).filter((held) => held.kind === kind);

  async function load() {
    loading = true;

    const answer = await feedback.attempt(() => api.query(QUERY));

    loading = false;

    if (answer) data = answer;
  }

  load();

  function blankConfig(service) {
    return Object.fromEntries(
      service.fields.map((field) => [
        field.key,
        field.secret ? "" : (field.default ?? (field.type === "boolean" ? false : "")),
      ]),
    );
  }

  function add(kind) {
    const service = services.find((held) => held.kind === kind);

    editing = "";
    draft = {
      kind,
      service: service.service,
      key: "",
      name: "",
      primary: forKind(data.active, kind).length === 0,
      config: blankConfig(service),
    };
    feedback.clear();
  }

  function pick(name) {
    const service = serviceOf(name);

    draft.service = name;
    draft.config = blankConfig(service);

    if (!draft.key) draft.key = name.replace(/_/g, "-");
    if (!draft.name) draft.name = service.label;
  }

  function edit(sender) {
    const service = serviceOf(sender.service);

    editing = sender.key;
    draft = {
      kind: sender.kind,
      service: sender.service,
      key: sender.key,
      name: sender.name,
      primary: sender.primary,
      secretsHeld: sender.secretsHeld,
      config: Object.fromEntries(
        service.fields.map((field) => [
          field.key,
          field.secret ? "" : (sender.settings[field.key] ?? field.default ?? ""),
        ]),
      ),
    };
    feedback.clear();
  }

  function close() {
    editing = null;
    draft = null;
    feedback.clear();
  }

  function config() {
    const service = serviceOf(draft.service);

    return Object.fromEntries(
      service.fields
        .filter((field) => !(field.secret && !draft.config[field.key]))
        .map((field) => [
          field.key,
          field.type === "integer" ? Number(draft.config[field.key]) || null : draft.config[field.key],
        ]),
    );
  }

  async function save() {
    busy = true;

    const fresh = editing === "";
    const done = await feedback.attempt(
      () =>
        fresh
          ? api.query(
              `mutation Create($key: ID!, $service: String!, $name: String!, $config: JSON, $primary: Boolean) {
                createSender(key: $key, service: $service, name: $name, config: $config, primary: $primary) {
                  sender { key }
                }
              }`,
              {
                key: draft.key.trim(),
                service: draft.service,
                name: draft.name.trim(),
                config: config(),
                primary: draft.primary,
              },
            )
          : api.query(
              `mutation Update($key: ID!, $name: String, $config: JSON, $primary: Boolean) {
                updateSender(key: $key, name: $name, config: $config, primary: $primary) {
                  sender { key }
                }
              }`,
              { key: draft.key, name: draft.name.trim(), config: config(), primary: draft.primary },
            ),
      fresh ? t("senders.added", { name: draft.name }) : t("senders.saved", { name: draft.name }),
    );

    busy = false;

    if (!done) return;

    close();
    await load();
  }

  async function act(mutation, sender, notice, question = null) {
    if (question && !confirm(question)) return;

    const done = await feedback.attempt(
      () =>
        api.query(`mutation Act($key: ID!) { ${mutation}(key: $key) { sender { key } } }`, {
          key: sender.key,
        }),
      notice,
    );

    if (done) await load();
  }

  async function makePrimary(sender) {
    const done = await feedback.attempt(
      () =>
        api.query(
          `mutation Primary($key: ID!) { updateSender(key: $key, primary: true) { sender { key } } }`,
          { key: sender.key },
        ),
      t("senders.primary_notice", { name: sender.name }),
    );

    if (done) await load();
  }

  async function test(sender) {
    const to = (testing[sender.key] ?? "").trim();

    if (!to) return;

    busy = true;

    const answer = await feedback.attempt(() =>
      api.query(
        `mutation Test($key: ID!, $to: String!) { testSender(key: $key, to: $to) { delivered failure } }`,
        { key: sender.key, to },
      ),
    );

    busy = false;

    if (!answer) return;

    if (answer.testSender.delivered) {
      feedback.say(t("senders.tested", { name: sender.name, to }));
    } else {
      feedback.blame(answer.testSender.failure);
    }
  }

  const complete = $derived.by(() => {
    if (!draft) return false;

    const service = serviceOf(draft.service);

    return (
      draft.key.trim() &&
      draft.name.trim() &&
      service.fields.every(
        (field) =>
          !field.required ||
          field.type === "boolean" ||
          (field.secret && draft.secretsHeld?.includes(field.key)) ||
          String(draft.config[field.key] ?? "").trim(),
      )
    );
  });
</script>

<div class="console-page">
  <Notices feedback={feedback.state} />

  {#if loading && !data}
    <Spinner />
  {:else if data}
    {#if draft}
      <Section title={editing === "" ? t("senders.form.add") : t("senders.form.edit", { name: draft.name })}>
        {#if editing === ""}
          <label class="flex flex-col gap-1.5">
            <span class="field-label">{t("senders.form.service")}</span>
            <select
              class="select select-sm w-full"
              value={draft.service}
              onchange={(event) => pick(event.currentTarget.value)}
            >
              {#each services.filter((held) => held.kind === draft.kind) as service (service.service)}
                <option value={service.service}>{service.label}</option>
              {/each}
            </select>
          </label>
        {/if}

        <div class="grid gap-3 sm:grid-cols-2">
          <Field
            label={t("senders.form.key")}
            bind:value={draft.key}
            disabled={editing !== ""}
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
          />
          <Field label={t("senders.form.name")} bind:value={draft.name} />
        </div>

        <div class="grid gap-3 sm:grid-cols-2">
          {#each serviceOf(draft.service).fields as field (field.key)}
            {#if field.type === "boolean"}
              <div class="flex flex-col gap-1 sm:col-span-2">
                <Switch label={field.label} bind:checked={draft.config[field.key]} />
                {#if field.hint}<p class="hint">{field.hint}</p>{/if}
              </div>
            {:else if field.options}
              <label class="flex flex-col gap-1.5">
                <span class="field-label">{field.label}</span>
                <select class="select select-sm w-full" bind:value={draft.config[field.key]}>
                  {#each field.options as option (option)}
                    <option value={option}>{option}</option>
                  {/each}
                </select>
              </label>
            {:else}
              <div class="flex flex-col gap-1">
                <Field
                  label={field.required ? field.label : t("senders.form.optional", { label: field.label })}
                  type={field.secret ? "password" : field.type === "integer" ? "number" : "text"}
                  bind:value={draft.config[field.key]}
                  autocomplete="off"
                  autocapitalize="none"
                  spellcheck="false"
                  placeholder={field.secret && draft.secretsHeld?.includes(field.key) ? t("senders.form.unchanged") : ""}
                />
                {#if field.hint}<p class="hint">{field.hint}</p>{/if}
              </div>
            {/if}
          {/each}
        </div>

        <Switch label={t("senders.form.primary")} bind:checked={draft.primary} />

        <div class="flex gap-2">
          <button type="button" class="btn btn-primary btn-sm" disabled={busy || !complete} onclick={save}>
            {editing === "" ? t("senders.form.create") : t("senders.form.save")}
          </button>
          <button type="button" class="btn btn-ghost btn-sm" onclick={close}>{t("senders.form.cancel")}</button>
        </div>
      </Section>
    {/if}

    {#each KINDS as group (group.kind)}
      {@const held = forKind(data.active, group.kind)}

      <Section title={group.title} lede={held.length ? group.lede : group.idle}>
        {#snippet actions()}
          <button type="button" class="btn btn-sm" onclick={() => add(group.kind)}>{t("senders.list.add")}</button>
        {/snippet}

        {#each held as sender (sender.key)}
          <div class="flex flex-col gap-3 sheet p-3">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <div class="flex min-w-0 flex-col">
                <span class="font-medium">
                  {sender.name}
                  {#if sender.primary}<span class="badge badge-success badge-sm">{t("senders.list.primary")}</span>{/if}
                </span>
                <span class="hint">
                  {sender.label} · <span class="font-mono">{sender.key}</span> · {t("senders.list.added", { day: day(sender.createdAt) })}
                </span>
              </div>

              <div class="flex flex-wrap gap-2">
                {#if !sender.primary}
                  <button type="button" class="btn btn-ghost btn-sm" onclick={() => makePrimary(sender)}>
                    {t("senders.list.make_primary")}
                  </button>
                {/if}
                <button type="button" class="btn btn-sm" onclick={() => edit(sender)}>{t("senders.list.edit")}</button>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm"
                  onclick={() =>
                    act(
                      "archiveSender",
                      sender,
                      t("senders.archived_notice", { name: sender.name }),
                      t("senders.archive_confirm", { name: sender.name }),
                    )}
                >
                  {t("senders.list.archive")}
                </button>
              </div>
            </div>

            <Field
              label={t("senders.list.test_to")}
              bind:value={testing[sender.key]}
              placeholder={group.to}
              save={t("senders.list.test")}
              onsave={() => test(sender)}
            />
          </div>
        {/each}
      </Section>
    {/each}

    {#if data.archived.length}
      <Section title={t("senders.archived.title")}>
        {#each data.archived as sender (sender.key)}
          <div class="flex flex-wrap items-center justify-between gap-2">
            <span class="text-sm">
              {sender.name} <span class="hint">{sender.label} · {sender.kind}</span>
            </span>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              onclick={() => act("restoreSender", sender, t("senders.restored", { name: sender.name }))}
            >
              {t("senders.archived.restore")}
            </button>
          </div>
        {/each}
      </Section>
    {/if}
  {/if}
</div>
