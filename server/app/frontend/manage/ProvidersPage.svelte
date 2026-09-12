<script>
  import Connections from "./Connections.svelte";
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
    issuer jwksUri signsIn provisions emailDomains signupScopes
  `;

  const SSO_ARGS = `
    $issuer: String, $jwksUri: String, $signsIn: Boolean, $provisions: Boolean,
    $emailDomains: [String!], $signupScopes: [String!]
  `;

  const SSO_PASS = `
    issuer: $issuer, jwksUri: $jwksUri, signsIn: $signsIn, provisions: $provisions,
    emailDomains: $emailDomains, signupScopes: $signupScopes
  `;

  const DISCOVER = `
    mutation Discover($issuer: String!) {
      discoverProvider(issuer: $issuer) {
        issuer authorizationUrl tokenUrl userinfoUrl revocationUrl jwksUri
      }
    }
  `;

  const QUERY = `
    query Providers {
      active: providers { ${FIELDS} }
      archived: providers(archived: true) { ${FIELDS} }
      connections {
        id subject label email emailVerified connectedAt signedInAt
        provider { key name releaseScope }
        actor { uuid identifier }
      }
    }
  `;

  const CREATE = `
    mutation Create(
      $key: ID!, $name: String!, $authorizationUrl: String!, $tokenUrl: String!,
      $clientId: String!, $clientSecret: String, $revocationUrl: String,
      $userinfoUrl: String, $scopes: [String!], $subjectClaim: String, $labelClaim: String,
      ${SSO_ARGS}
    ) {
      createProvider(
        key: $key, name: $name, authorizationUrl: $authorizationUrl, tokenUrl: $tokenUrl,
        clientId: $clientId, clientSecret: $clientSecret, revocationUrl: $revocationUrl,
        userinfoUrl: $userinfoUrl, scopes: $scopes, subjectClaim: $subjectClaim,
        labelClaim: $labelClaim, ${SSO_PASS}
      ) { provider { key } }
    }
  `;

  const UPDATE = `
    mutation Update(
      $key: ID!, $name: String, $authorizationUrl: String, $tokenUrl: String,
      $clientId: String, $clientSecret: String, $revocationUrl: String,
      $userinfoUrl: String, $scopes: [String!], $subjectClaim: String, $labelClaim: String,
      ${SSO_ARGS}
    ) {
      updateProvider(
        key: $key, name: $name, authorizationUrl: $authorizationUrl, tokenUrl: $tokenUrl,
        clientId: $clientId, clientSecret: $clientSecret, revocationUrl: $revocationUrl,
        userinfoUrl: $userinfoUrl, scopes: $scopes, subjectClaim: $subjectClaim,
        labelClaim: $labelClaim, ${SSO_PASS}
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
    issuer: "",
    jwksUri: "",
    signsIn: false,
    provisions: false,
    emailDomains: "",
    signupScopes: "",
  };

  const feedback = createFeedback();

  let active = $state([]);
  let archived = $state([]);
  let connected = $state([]);
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
    connected = data.connections;
  }

  const connectionsFor = (provider) =>
    connected.filter((held) => held.provider.key === provider.key);

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
      issuer: provider.issuer ?? "",
      jwksUri: provider.jwksUri ?? "",
      signsIn: provider.signsIn,
      provisions: provider.provisions,
      emailDomains: provider.emailDomains.join(" "),
      signupScopes: provider.signupScopes.join(" "),
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
      issuer: trimmed(draft.issuer),
      jwksUri: trimmed(draft.jwksUri),
      signsIn: draft.signsIn,
      provisions: draft.provisions,
      emailDomains: draft.emailDomains.split(/[\s,]+/).filter(Boolean),
      signupScopes: draft.signupScopes.split(/[\s,]+/).filter(Boolean),
    };
  }

  async function discover() {
    busy = true;

    const data = await feedback.attempt(
      () => api.query(DISCOVER, { issuer: draft.issuer.trim() }),
      "Endpoints filled in from the discovery document.",
    );

    busy = false;

    if (!data) return;

    const found = data.discoverProvider;

    draft.issuer = found.issuer;
    draft.authorizationUrl = found.authorizationUrl;
    draft.tokenUrl = found.tokenUrl;
    draft.jwksUri = found.jwksUri;
    draft.userinfoUrl = found.userinfoUrl ?? draft.userinfoUrl;
    draft.revocationUrl = found.revocationUrl ?? draft.revocationUrl;
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

      <div class="flex flex-wrap items-end gap-3">
        <div class="min-w-64 flex-1">
          <Field
            label="Issuer"
            bind:value={draft.issuer}
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
            placeholder="https://accounts.google.com"
          />
        </div>
        <button
          type="button"
          class="btn btn-sm"
          disabled={busy || !draft.issuer.trim()}
          onclick={discover}
        >
          Discover
        </button>
      </div>

      <p class="text-xs opacity-60">
        Needed to sign people in — the id_token is checked against this issuer and its published
        keys. Leave it empty for a provider that only ever brokers a connection.
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
        <Field
          label="JWKS URI"
          bind:value={draft.jwksUri}
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          placeholder="discovered if left empty"
        />
      </div>

      <div class="flex flex-col gap-3 rounded-lg bg-base-200 p-3">
        <span class="legend">Signing in</span>

        <label class="flex items-start gap-3 text-sm">
          <input type="checkbox" class="toggle toggle-sm" bind:checked={draft.signsIn} />
          <span>
            People can sign in with {draft.name.trim() || "this provider"}
            <span class="block text-xs opacity-60">
              A button appears on the sign-in page. It counts as a password, not as a second factor.
            </span>
          </span>
        </label>

        <label class="flex items-start gap-3 text-sm">
          <input
            type="checkbox"
            class="toggle toggle-sm"
            disabled={!draft.signsIn}
            bind:checked={draft.provisions}
          />
          <span>
            Create an account for somebody new
            <span class="block text-xs opacity-60">
              Off, only people who already have an account here can sign in. A confirmed address
              always links to the account that holds it; an unconfirmed one never does.
            </span>
          </span>
        </label>

        {#if draft.signsIn}
          <div class="grid gap-3 sm:grid-cols-2">
            <Field
              label="Allowed email domains"
              bind:value={draft.emailDomains}
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              placeholder="any domain"
            />
            {#if draft.provisions}
              <Field
                label="Scopes for a new account"
                bind:value={draft.signupScopes}
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
                placeholder="openid profile email offline_access"
              />
            {/if}
          </div>
        {/if}
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

        <div class="flex flex-wrap gap-2">
          {#if provider.signsIn}
            <span class="badge badge-success badge-sm">signs people in</span>
            {#if provider.provisions}
              <span class="badge badge-warning badge-sm">creates accounts</span>
            {:else}
              <span class="badge badge-ghost badge-sm">existing accounts only</span>
            {/if}
            {#each provider.emailDomains as domain (domain)}
              <span class="badge badge-ghost badge-sm font-mono">@{domain}</span>
            {/each}
          {:else}
            <span class="badge badge-ghost badge-sm">connections only</span>
          {/if}
        </div>

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
            <dd>
              {provider.connections}
              {#if provider.signedIn}
                <span class="text-xs opacity-60">· {provider.signedIn} sign in with it</span>
              {/if}
            </dd>
          </div>
        </dl>

        {#if connectionsFor(provider).length}
          <details class="text-sm">
            <summary class="cursor-pointer opacity-70">
              Who is connected ({connectionsFor(provider).length})
            </summary>

            <div class="pt-3">
              <Connections
                {api}
                {feedback}
                rows={connectionsFor(provider)}
                onchange={load}
                showActor
              />
            </div>
          </details>
        {/if}
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
