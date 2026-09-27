<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api } = $props();

  const FIELDS = `key name url actions lastDeliveredAt lastFailure archivedAt createdAt`;

  const QUERY = `
    query Streams {
      active: eventStreams { ${FIELDS} }
      archived: eventStreams(archived: true) { ${FIELDS} }
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
    draft = { key: "", name: "", url: "", actions: "" };
    secret = null;
    feedback.clear();
  }

  function edit(stream) {
    editing = stream.key;
    draft = { key: stream.key, name: stream.name, url: stream.url, actions: stream.actions.join("\n") };
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
    };

    const answer = await feedback.attempt(
      () =>
        fresh
          ? api.query(
              `mutation Create($key: ID!, $name: String!, $url: String!, $actions: [String!]) {
                createEventStream(key: $key, name: $name, url: $url, actions: $actions) { secret }
              }`,
              variables,
            )
          : api.query(
              `mutation Update($key: ID!, $name: String, $url: String, $actions: [String!]) {
                updateEventStream(key: $key, name: $name, url: $url, actions: $actions) { eventStream { key } }
              }`,
              variables,
            ),
      fresh ? `${draft.name} added.` : `${draft.name} saved.`,
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
    if (!confirm(`Rotate the secret for ${stream.name}? Deliveries signed with the old secret stop verifying.`)) return;

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
      feedback.say(`${stream.name} accepted a test event.`);
    } else {
      feedback.blame(answer.testEventStream.failure);
    }

    await load();
  }

  const complete = $derived(draft?.key.trim() && draft.name.trim() && draft.url.trim());
</script>

<Page title="Event streams">
  <Notices feedback={feedback.state} />

  {#if loading && !data}
    <Spinner />
  {:else if data}
    {#if secret}
      <Section
        title="Signing secret"
        lede="Verify the Masks-Signature header of each delivery with this secret. It is shown once."
      >
        <input class="input input-sm w-full font-mono" readonly value={secret} onfocus={(event) => event.currentTarget.select()} />
        <div>
          <button type="button" class="btn btn-ghost btn-sm" onclick={() => (secret = null)}>I have saved it</button>
        </div>
      </Section>
    {/if}

    {#if draft}
      <Section title={editing === "" ? "Add event stream" : `Edit ${draft.name}`}>
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

        <Field
          label="Address"
          type="url"
          bind:value={draft.url}
          placeholder="https://siem.example.com/masks"
          autocapitalize="none"
          spellcheck="false"
        />

        <label class="flex flex-col gap-1.5">
          <span class="field-label">Actions (optional)</span>
          <textarea
            class="textarea w-full font-mono"
            rows="4"
            bind:value={draft.actions}
            placeholder="session.started&#10;actor.deleted"
          ></textarea>
          <p class="hint">One action per line. Leave it empty to stream every action.</p>
        </label>

        <div class="flex gap-2">
          <button type="button" class="btn btn-primary btn-sm" disabled={busy || !complete} onclick={save}>
            {editing === "" ? "Add" : "Save"}
          </button>
          <button type="button" class="btn btn-ghost btn-sm" onclick={close}>Cancel</button>
        </div>
      </Section>
    {/if}

    <Section
      title="Streams"
      lede={data.active.length
        ? "Each event a tenant records is posted, signed, to every stream that wants it."
        : "Nothing leaves masks until a stream is added."}
    >
      {#snippet actions()}
        <button type="button" class="btn btn-sm" onclick={add}>Add</button>
      {/snippet}

      {#each data.active as stream (stream.key)}
        <div class="flex flex-col gap-3 rounded-lg border border-base-300 p-3">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div class="flex min-w-0 flex-col">
              <span class="font-medium">{stream.name}</span>
              <span class="hint break-all">
                <span class="font-mono">{stream.key}</span> · {stream.url} · added {day(stream.createdAt)}
              </span>
              <span class="hint">
                {stream.actions.length ? stream.actions.join(", ") : "Every action"}
              </span>
              {#if stream.lastFailure}
                <span class="text-sm text-error">{stream.lastFailure}</span>
              {:else if stream.lastDeliveredAt}
                <span class="hint">Last delivered {day(stream.lastDeliveredAt)}</span>
              {/if}
            </div>

            <div class="flex flex-wrap gap-2">
              <button type="button" class="btn btn-sm" disabled={busy} onclick={() => test(stream)}>Send a test</button>
              <button type="button" class="btn btn-sm" onclick={() => edit(stream)}>Edit</button>
              <button type="button" class="btn btn-ghost btn-sm" onclick={() => rotate(stream)}>Rotate secret</button>
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                onclick={() =>
                  act(
                    "archiveEventStream",
                    stream,
                    `${stream.name} is archived.`,
                    `Archive ${stream.name}? Nothing is delivered to it until it is restored.`,
                  )}
              >
                Archive
              </button>
            </div>
          </div>
        </div>
      {/each}
    </Section>

    {#if data.archived.length}
      <Section title="Archived">
        {#each data.archived as stream (stream.key)}
          <div class="flex flex-wrap items-center justify-between gap-2">
            <span class="text-sm">{stream.name} <span class="hint">{stream.url}</span></span>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              onclick={() => act("restoreEventStream", stream, `${stream.name} is back.`)}
            >
              Restore
            </button>
          </div>
        {/each}
      </Section>
    {/if}
  {/if}
</Page>
