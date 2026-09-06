<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import Card from "./ui/Card.svelte";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api } = $props();

  const FIELDS = `
    key name authorizationUrl tokenUrl revocationUrl userinfoUrl clientId
    scopes authorizeParams subjectClaim labelClaim releaseScope
    secretHeld connections archivedAt createdAt
  `;

  const QUERY = `
    query Providers {
      active: providers { ${FIELDS} }
      archived: providers(archived: true) { ${FIELDS} }
    }
  `;

  const CREATE = `
    mutation Create(
      $key: ID!, $name: String!, $authorizationUrl: String!, $tokenUrl: String!,
      $clientId: String!, $clientSecret: String, $revocationUrl: String,
      $userinfoUrl: String, $scopes: [String!], $subjectClaim: String, $labelClaim: String
    ) {
      createProvider(
        key: $key, name: $name, authorizationUrl: $authorizationUrl, tokenUrl: $tokenUrl,
        clientId: $clientId, clientSecret: $clientSecret, revocationUrl: $revocationUrl,
        userinfoUrl: $userinfoUrl, scopes: $scopes, subjectClaim: $subjectClaim,
        labelClaim: $labelClaim
      ) { provider { key } }
    }
  `;

  const UPDATE = `
    mutation Update(
      $key: ID!, $name: String, $authorizationUrl: String, $tokenUrl: String,
      $clientId: String, $clientSecret: String, $revocationUrl: String,
      $userinfoUrl: String, $scopes: [String!], $subjectClaim: String, $labelClaim: String
    ) {
      updateProvider(
        key: $key, name: $name, authorizationUrl: $authorizationUrl, tokenUrl: $tokenUrl,
        clientId: $clientId, clientSecret: $clientSecret, revocationUrl: $revocationUrl,
        userinfoUrl: $userinfoUrl, scopes: $scopes, subjectClaim: $subjectClaim,
        labelClaim: $labelClaim
      ) { provider { key } }
    }
  `;

  const BLANK = {
    key: "",
    name: "",
    authorizationUrl: "",
    tokenUrl: "",
    revocationUrl: "",
    userinfoUrl: "",
    clientId: "",
    clientSecret: "",
    scopes: "",
    subjectClaim: "sub",
    labelClaim: "email",
  };

  const feedback = createFeedback();

  let active = $state([]);
  let archived = $state([]);
  let loading = $state(true);
  let busy = $state(false);
  let editing = $state(null);
  let draft = $state({ ...BLANK });

  async function load() {
    loading = true;

    const data = await feedback.attempt(() => api.query(QUERY));

    loading = false;

    if (!data) return;

    active = data.active;
    archived = data.archived;
  }

  load();

  function add() {
    editing = "";
    draft = { ...BLANK };
    feedback.clear();
  }

  function edit(provider) {
    editing = provider.key;
    draft = {
      key: provider.key,
      name: provider.name,
      authorizationUrl: provider.authorizationUrl,
      tokenUrl: provider.tokenUrl,
      revocationUrl: provider.revocationUrl ?? "",
      userinfoUrl: provider.userinfoUrl ?? "",
      clientId: provider.clientId,
      clientSecret: "",
      scopes: provider.scopes.join(" "),
      subjectClaim: provider.subjectClaim,
      labelClaim: provider.labelClaim,
    };
    feedback.clear();
  }

  function close() {
    editing = null;
    feedback.clear();
  }

  const trimmed = (value) => value.trim() || null;

  function variables() {
    return {
      key: draft.key.trim(),
      name: draft.name.trim(),
      authorizationUrl: draft.authorizationUrl.trim(),
      tokenUrl: draft.tokenUrl.trim(),
      revocationUrl: trimmed(draft.revocationUrl),
      userinfoUrl: trimmed(draft.userinfoUrl),
      clientId: draft.clientId.trim(),
      clientSecret: trimmed(draft.clientSecret),
      scopes: draft.scopes.split(/[\s,]+/).filter(Boolean),
      subjectClaim: draft.subjectClaim.trim() || "sub",
      labelClaim: draft.labelClaim.trim() || "email",
    };
  }

  async function save() {
    busy = true;

    const fresh = editing === "";
    const done = await feedback.attempt(
      () => api.query(fresh ? CREATE : UPDATE, variables()),
      fresh ? `${draft.name} can sign people in now.` : `${draft.name} saved.`,
    );

    busy = false;

    if (!done) return;

    editing = null;

    await load();
  }

  async function act(mutation, provider, notice, question = null) {
    if (question && !confirm(question)) return;

    const done = await feedback.attempt(
      () =>
        api.query(
          `mutation Act($key: ID!) { ${mutation}(key: $key) { provider { key } } }`,
          { key: provider.key },
        ),
      notice,
    );

    if (done) await load();
  }

  const archive = (provider) =>
    act(
      "archiveProvider",
      provider,
      `${provider.name} is archived.`,
      `Archive ${provider.name}? Nobody can connect a new account through it, and ${provider.connections} existing connection${provider.connections === 1 ? "" : "s"} stop being released.`,
    );

  const restore = (provider) => act("restoreProvider", provider, `${provider.name} is back.`);

  const complete = $derived(
    draft.key.trim() &&
      draft.name.trim() &&
      draft.authorizationUrl.trim() &&
      draft.tokenUrl.trim() &&
      draft.clientId.trim(),
  );
</script>

<Page
  title="Providers"
  lede="Upstream accounts people can connect. Each one publishes a scope an application asks for to be handed the connection."
>
  {#snippet actions()}
    <button type="button" class="btn btn-primary btn-sm" onclick={add}>Add a provider</button>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if editing !== null}
    <Card title={editing === "" ? "Add a provider" : `Edit ${draft.name}`}>
      <div class="grid gap-3 sm:grid-cols-2">
        <Field
          label="Key"
          bind:value={draft.key}
          disabled={editing !== ""}
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          placeholder="google"
        />
        <Field label="Name" bind:value={draft.name} placeholder="Google" />
      </div>

      <p class="text-xs opacity-60">
        The key names the scope: <span class="font-mono">masks:connections:{draft.key || "…"}</span>
      </p>

      <div class="grid gap-3 sm:grid-cols-2">
        <Field
          label="Authorization URL"
          bind:value={draft.authorizationUrl}
          placeholder="https://accounts.google.com/o/oauth2/v2/auth"
        />
        <Field
          label="Token URL"
          bind:value={draft.tokenUrl}
          placeholder="https://oauth2.googleapis.com/token"
        />
        <Field label="Revocation URL" bind:value={draft.revocationUrl} placeholder="optional" />
        <Field label="Userinfo URL" bind:value={draft.userinfoUrl} placeholder="optional" />
      </div>

      <div class="grid gap-3 sm:grid-cols-2">
        <Field label="Client ID" bind:value={draft.clientId} />
        <Field
          label="Client secret"
          type="password"
          bind:value={draft.clientSecret}
          autocomplete="off"
          placeholder={editing === "" ? "" : "unchanged"}
        />
      </div>

      <Field
        label="Scopes"
        bind:value={draft.scopes}
        autocapitalize="none"
        autocorrect="off"
        spellcheck="false"
        placeholder="https://www.googleapis.com/auth/drive.readonly"
      />

      <div class="grid gap-3 sm:grid-cols-2">
        <Field label="Subject claim" bind:value={draft.subjectClaim} />
        <Field label="Label claim" bind:value={draft.labelClaim} />
      </div>

      <div class="flex gap-2">
        <button
          type="button"
          class="btn btn-primary btn-sm"
          disabled={busy || !complete}
          onclick={save}
        >
          {busy ? "Saving..." : editing === "" ? "Add it" : "Save"}
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onclick={close}>Cancel</button>
      </div>
    </Card>
  {/if}

  {#if loading && active.length === 0 && archived.length === 0}
    <Spinner />
  {:else if active.length === 0 && archived.length === 0}
    <div class="rounded-box border border-base-300 bg-base-100 px-6 py-14 text-center">
      <p class="mx-auto max-w-sm text-sm opacity-70">
        No provider is set up. Add one and people can connect that account from their own page.
      </p>
    </div>
  {:else}
    {#each active as provider (provider.key)}
      <Card title={provider.name} lede={provider.releaseScope}>
        {#snippet actions()}
          <button type="button" class="btn btn-sm" onclick={() => edit(provider)}>Edit</button>
          <button
            type="button"
            class="btn btn-sm btn-error btn-outline"
            onclick={() => archive(provider)}
          >
            Archive
          </button>
        {/snippet}

        <dl class="grid gap-x-6 gap-y-2 text-sm sm:grid-cols-2">
          <div>
            <dt class="text-xs opacity-60">Client ID</dt>
            <dd class="font-mono break-all">{provider.clientId}</dd>
          </div>
          <div>
            <dt class="text-xs opacity-60">Secret</dt>
            <dd>
              {#if provider.secretHeld}
                held
              {:else}
                <span class="text-warning">none set</span>
              {/if}
            </dd>
          </div>
          <div>
            <dt class="text-xs opacity-60">Authorization</dt>
            <dd class="font-mono text-xs break-all">{provider.authorizationUrl}</dd>
          </div>
          <div>
            <dt class="text-xs opacity-60">Token</dt>
            <dd class="font-mono text-xs break-all">{provider.tokenUrl}</dd>
          </div>
          <div>
            <dt class="text-xs opacity-60">Scopes asked upstream</dt>
            <dd class="font-mono text-xs break-all">{provider.scopes.join(" ") || "—"}</dd>
          </div>
          <div>
            <dt class="text-xs opacity-60">Connections</dt>
            <dd>{provider.connections}</dd>
          </div>
        </dl>
      </Card>
    {/each}

    {#if archived.length}
      <Card title="Archived" lede="Kept so the connections made through them still make sense.">
        <ul class="flex flex-col gap-1.5">
          {#each archived as provider (provider.key)}
            <li class="slat">
              <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                <span class="flex flex-wrap items-baseline gap-2">
                  <span class="text-sm font-medium">{provider.name}</span>
                  <span class="font-mono text-xs opacity-50">{provider.releaseScope}</span>
                </span>

                <span class="flex items-baseline gap-3 text-xs">
                  <span class="opacity-60">archived {day(provider.archivedAt)}</span>
                  <button type="button" class="link" onclick={() => restore(provider)}>
                    Restore
                  </button>
                </span>
              </div>
            </li>
          {/each}
        </ul>
      </Card>
    {/if}
  {/if}
</Page>
