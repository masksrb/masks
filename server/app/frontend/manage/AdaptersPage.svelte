<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Switch from "./ui/Switch.svelte";

  let { api } = $props();

  const FIELDS = `key name kind service label primary settings secretsHeld archivedAt createdAt`;

  const QUERY = `
    query Adapters {
      active: adapters { ${FIELDS} }
      archived: adapters(archived: true) { ${FIELDS} }
      adapterServices {
        service kind label
        fields { key label type secret required options default hint }
      }
      tenant { mails texts }
    }
  `;

  const KINDS = [
    {
      kind: "mail",
      title: "Mail",
      lede: "Invitations, resets, confirmations and codes. The primary one sends everything.",
      idle: "Nothing is emailed from this tenant's own adapters. Mail falls back to whatever the deployment configured, if anything.",
      to: "you@example.com",
    },
    {
      kind: "sms",
      title: "Text messages",
      lede: "Phone confirmations and sign-in codes. The primary one sends everything.",
      idle: "No texts can be sent until an adapter is added.",
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

  const services = $derived(data?.adapterServices ?? []);
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

  function edit(adapter) {
    const service = serviceOf(adapter.service);

    editing = adapter.key;
    draft = {
      kind: adapter.kind,
      service: adapter.service,
      key: adapter.key,
      name: adapter.name,
      primary: adapter.primary,
      secretsHeld: adapter.secretsHeld,
      config: Object.fromEntries(
        service.fields.map((field) => [
          field.key,
          field.secret ? "" : (adapter.settings[field.key] ?? field.default ?? ""),
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
                createAdapter(key: $key, service: $service, name: $name, config: $config, primary: $primary) {
                  adapter { key }
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
                updateAdapter(key: $key, name: $name, config: $config, primary: $primary) {
                  adapter { key }
                }
              }`,
              { key: draft.key, name: draft.name.trim(), config: config(), primary: draft.primary },
            ),
      fresh ? `${draft.name} added.` : `${draft.name} saved.`,
    );

    busy = false;

    if (!done) return;

    close();
    await load();
  }

  async function act(mutation, adapter, notice, question = null) {
    if (question && !confirm(question)) return;

    const done = await feedback.attempt(
      () =>
        api.query(`mutation Act($key: ID!) { ${mutation}(key: $key) { adapter { key } } }`, {
          key: adapter.key,
        }),
      notice,
    );

    if (done) await load();
  }

  async function makePrimary(adapter) {
    const done = await feedback.attempt(
      () =>
        api.query(
          `mutation Primary($key: ID!) { updateAdapter(key: $key, primary: true) { adapter { key } } }`,
          { key: adapter.key },
        ),
      `${adapter.name} sends everything now.`,
    );

    if (done) await load();
  }

  async function test(adapter) {
    const to = (testing[adapter.key] ?? "").trim();

    if (!to) return;

    busy = true;

    const answer = await feedback.attempt(() =>
      api.query(
        `mutation Test($key: ID!, $to: String!) { testAdapter(key: $key, to: $to) { delivered failure } }`,
        { key: adapter.key, to },
      ),
    );

    busy = false;

    if (!answer) return;

    if (answer.testAdapter.delivered) {
      feedback.say(`${adapter.name} handed a test message to ${to}.`);
    } else {
      feedback.blame(answer.testAdapter.failure);
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

<Page
  title="Adapters"
>
  <Notices feedback={feedback.state} />

  {#if loading && !data}
    <Spinner />
  {:else if data}
    {#if draft}
      <Section title={editing === "" ? "Add adapter" : `Edit ${draft.name}`}>
        {#if editing === ""}
          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium opacity-70">Service</span>
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
            label="Key"
            bind:value={draft.key}
            disabled={editing !== ""}
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
          />
          <Field label="Name" bind:value={draft.name} />
        </div>

        <div class="grid gap-3 sm:grid-cols-2">
          {#each serviceOf(draft.service).fields as field (field.key)}
            {#if field.type === "boolean"}
              <div class="flex flex-col gap-1 sm:col-span-2">
                <Switch label={field.label} bind:checked={draft.config[field.key]} />
                {#if field.hint}<p class="text-xs opacity-60">{field.hint}</p>{/if}
              </div>
            {:else if field.options}
              <label class="flex flex-col gap-1.5">
                <span class="text-xs font-medium opacity-70">{field.label}</span>
                <select class="select select-sm w-full" bind:value={draft.config[field.key]}>
                  {#each field.options as option (option)}
                    <option value={option}>{option}</option>
                  {/each}
                </select>
              </label>
            {:else}
              <div class="flex flex-col gap-1">
                <Field
                  label={field.required ? field.label : `${field.label} (optional)`}
                  type={field.secret ? "password" : field.type === "integer" ? "number" : "text"}
                  bind:value={draft.config[field.key]}
                  autocomplete="off"
                  autocapitalize="none"
                  spellcheck="false"
                  placeholder={field.secret && draft.secretsHeld?.includes(field.key) ? "unchanged" : ""}
                />
                {#if field.hint}<p class="text-xs opacity-60">{field.hint}</p>{/if}
              </div>
            {/if}
          {/each}
        </div>

        <Switch label="Primary — send everything of this kind through it" bind:checked={draft.primary} />

        <div class="flex gap-2">
          <button type="button" class="btn btn-primary btn-sm" disabled={busy || !complete} onclick={save}>
            {editing === "" ? "Add" : "Save"}
          </button>
          <button type="button" class="btn btn-ghost btn-sm" onclick={close}>Cancel</button>
        </div>
      </Section>
    {/if}

    {#each KINDS as group (group.kind)}
      {@const held = forKind(data.active, group.kind)}

      <Section title={group.title} lede={held.length ? group.lede : group.idle}>
        {#snippet actions()}
          <button type="button" class="btn btn-sm" onclick={() => add(group.kind)}>Add</button>
        {/snippet}

        {#each held as adapter (adapter.key)}
          <div class="flex flex-col gap-3 rounded-lg border border-base-300 p-3">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <div class="flex min-w-0 flex-col">
                <span class="font-medium">
                  {adapter.name}
                  {#if adapter.primary}<span class="badge badge-success badge-sm">Primary</span>{/if}
                </span>
                <span class="text-xs opacity-60">
                  {adapter.label} · <span class="font-mono">{adapter.key}</span> · added {day(adapter.createdAt)}
                </span>
              </div>

              <div class="flex flex-wrap gap-2">
                {#if !adapter.primary}
                  <button type="button" class="btn btn-ghost btn-sm" onclick={() => makePrimary(adapter)}>
                    Make primary
                  </button>
                {/if}
                <button type="button" class="btn btn-sm" onclick={() => edit(adapter)}>Edit</button>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm"
                  onclick={() =>
                    act(
                      "archiveAdapter",
                      adapter,
                      `${adapter.name} is archived.`,
                      `Archive ${adapter.name}? Nothing is sent through it until it is restored.`,
                    )}
                >
                  Archive
                </button>
              </div>
            </div>

            <Field
              label="Send a test to"
              bind:value={testing[adapter.key]}
              placeholder={group.to}
              save="Send a test"
              onsave={() => test(adapter)}
            />
          </div>
        {/each}
      </Section>
    {/each}

    {#if data.archived.length}
      <Section title="Archived">
        {#each data.archived as adapter (adapter.key)}
          <div class="flex flex-wrap items-center justify-between gap-2">
            <span class="text-sm">
              {adapter.name} <span class="text-xs opacity-60">{adapter.label} · {adapter.kind}</span>
            </span>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              onclick={() => act("restoreAdapter", adapter, `${adapter.name} is back.`)}
            >
              Restore
            </button>
          </div>
        {/each}
      </Section>
    {/if}
  {/if}
</Page>
