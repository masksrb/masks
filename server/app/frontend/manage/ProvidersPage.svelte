<script>
  import Connections from "./Connections.svelte";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api } = $props();

  const PROTOCOLS = { oidc: "OpenID Connect", oauth2: "OAuth 2.0", saml: "SAML 2.0", mcp: "MCP server" };

  const MAPPED = [
    ["email", "Email"],
    ["email_verified", "Email confirmed"],
    ["name", "Name"],
    ["given_name", "Given name"],
    ["family_name", "Family name"],
    ["preferred_username", "Username"],
    ["picture", "Picture"],
  ];

  const NAME_ID_FORMATS = [
    ["", "Whatever the identity provider sends"],
    ["urn:oasis:names:tc:SAML:2.0:nameid-format:persistent", "Persistent"],
    ["urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress", "Email address"],
    ["urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified", "Unspecified"],
  ];

  const ASKED = {
    domain: ["Domain", "acme.okta.com"],
    tenant: ["Directory (tenant) ID", "00000000-0000-0000-0000-000000000000"],
    realm: ["Realm", "staff"],
  };

  const FIELDS = `
    key name protocol preset authorizationUrl tokenUrl userinfoUrl emailsUrl clientId
    scopes authorizeParams subjectClaim claims tokenAuthMethod responseMode teamId keyId
    secretHeld privateKeyHeld connections signedIn archivedAt createdAt callbackUrl
    issuer jwksUri role trustsEmail emailDomains signupScopes
    idpEntityId idpSsoUrl idpCertificates metadataUrl metadataFetchedAt nameIdFormat spEntityId
    delegates delegatedScopes delegationParams delegationScope resourceUrl registeredAt delegations
  `;

  const QUERY = `
    query Providers {
      active: providers { ${FIELDS} }
      archived: providers(archived: true) { ${FIELDS} }
      providerPresets { key name protocol asks needs defaults guide custom trustsEmail delegates delegatedScopes }
      connections {
        id subject label email emailVerified connectedAt signedInAt delegable
        provider { key name }
        actor { uuid identifier }
        delegations { id releasedAt client { clientId name } }
      }
    }
  `;

  const ARGUMENTS = [
    ["name", "String"],
    ["protocol", "String"],
    ["authorizationUrl", "String"],
    ["tokenUrl", "String"],
    ["userinfoUrl", "String"],
    ["emailsUrl", "String"],
    ["clientId", "String"],
    ["clientSecret", "String"],
    ["scopes", "[String!]"],
    ["subjectClaim", "String"],
    ["claims", "JSON"],
    ["issuer", "String"],
    ["jwksUri", "String"],
    ["tokenAuthMethod", "String"],
    ["responseMode", "String"],
    ["teamId", "String"],
    ["keyId", "String"],
    ["privateKey", "String"],
    ["idpEntityId", "String"],
    ["idpSsoUrl", "String"],
    ["idpCertificates", "String"],
    ["metadataUrl", "String"],
    ["nameIdFormat", "String"],
    ["role", "String"],
    ["trustsEmail", "Boolean"],
    ["emailDomains", "[String!]"],
    ["signupScopes", "[String!]"],
    ["delegates", "Boolean"],
    ["delegatedScopes", "[String!]"],
    ["delegationParams", "JSON"],
    ["resourceUrl", "String"],
  ];

  const declared = (extra) =>
    [...extra, ...ARGUMENTS].map(([name, type]) => `$${name}: ${type}`).join(", ");

  const passed = (extra) => [...extra, ...ARGUMENTS].map(([name]) => `${name}: $${name}`).join(", ");

  const CREATE_EXTRA = [
    ["key", "ID!"],
    ["preset", "ID"],
    ["presetValues", "JSON"],
  ];

  const CREATE = `
    mutation Create(${declared(CREATE_EXTRA).replace("$name: String", "$name: String!")}) {
      createProvider(${passed(CREATE_EXTRA)}) { provider { key callbackUrl } }
    }
  `;

  const UPDATE = `
    mutation Update(${declared([["key", "ID!"]])}) {
      updateProvider(${passed([["key", "ID!"]])}) { provider { key } }
    }
  `;

  const DISCOVER = `
    mutation Discover($issuer: String!) {
      discoverProvider(issuer: $issuer) { issuer authorizationUrl tokenUrl userinfoUrl jwksUri }
    }
  `;

  const METADATA = `
    mutation Metadata($metadataUrl: String, $metadataXml: String) {
      readSamlMetadata(metadataUrl: $metadataUrl, metadataXml: $metadataXml) {
        idpEntityId idpSsoUrl idpCertificates
      }
    }
  `;

  const blank = (preset) => ({
    key: preset.custom ? "" : preset.key,
    name: preset.custom ? "" : preset.name,
    preset: preset.custom ? null : preset.key,
    protocol: preset.protocol,
    asked: { ...preset.defaults },
    authorizationUrl: "",
    tokenUrl: "",
    userinfoUrl: "",
    emailsUrl: "",
    clientId: "",
    clientSecret: "",
    scopes: "",
    subjectClaim: preset.protocol === "oidc" ? "sub" : preset.protocol === "saml" ? "name_id" : "id",
    claims: {},
    issuer: "",
    jwksUri: "",
    tokenAuthMethod: preset.needs.includes("private_key") ? "signed_secret" : "client_secret_post",
    responseMode: "",
    teamId: "",
    keyId: "",
    privateKey: "",
    idpEntityId: "",
    idpSsoUrl: "",
    idpCertificates: "",
    metadataUrl: "",
    metadataXml: "",
    nameIdFormat: "",
    role: "credential",
    trustsEmail: Boolean(preset.trustsEmail),
    emailDomains: "",
    signupScopes: "",
    delegates: Boolean(preset.delegates),
    delegatedScopes: (preset.delegatedScopes ?? []).join(" "),
    delegationParams: "",
    resourceUrl: "",
  });

  const feedback = createFeedback();

  let active = $state([]);
  let archived = $state([]);
  let presets = $state([]);
  let connected = $state([]);
  let loading = $state(true);
  let busy = $state(false);
  let picking = $state(false);
  let editing = $state(null);
  let chosen = $state(null);
  let draft = $state(null);

  async function load() {
    loading = true;

    const data = await feedback.attempt(() => api.query(QUERY));

    loading = false;

    if (!data) return;

    active = data.active;
    archived = data.archived;
    presets = data.providerPresets;
    connected = data.connections;
  }

  load();

  const connectionsFor = (provider) =>
    connected.filter((held) => held.provider.key === provider.key);

  const presetNamed = (key) => presets.find((preset) => preset.key === key);

  const fresh = $derived(editing === "");
  const custom = $derived(fresh ? Boolean(chosen?.custom) : true);
  const saml = $derived(draft?.protocol === "saml");
  const oauth2 = $derived(draft?.protocol === "oauth2");
  const oidc = $derived(draft?.protocol === "oidc");
  const mcp = $derived(draft?.protocol === "mcp");
  const signsSecret = $derived(draft?.tokenAuthMethod === "signed_secret");
  const origin = typeof window === "undefined" ? "" : window.location.origin;
  const callbackUrl = $derived(`${origin}/login/provider/${draft?.key?.trim() || "…"}/callback`);
  const spEntityId = $derived(`${origin}/login/provider/${draft?.key?.trim() || "…"}/metadata`);

  function add() {
    picking = true;
    editing = null;
    draft = null;
    feedback.clear();
  }

  function pick(preset) {
    chosen = preset;
    picking = false;
    editing = "";
    draft = blank(preset);
    feedback.clear();
  }

  function edit(provider) {
    picking = false;
    chosen = presetNamed(provider.preset) ?? null;
    editing = provider.key;
    draft = {
      ...blank({ key: provider.key, name: provider.name, protocol: provider.protocol, needs: [], defaults: {}, custom: true }),
      key: provider.key,
      name: provider.name,
      preset: provider.preset,
      authorizationUrl: provider.authorizationUrl ?? "",
      tokenUrl: provider.tokenUrl ?? "",
      userinfoUrl: provider.userinfoUrl ?? "",
      emailsUrl: provider.emailsUrl ?? "",
      clientId: provider.clientId ?? "",
      scopes: provider.scopes.join(" "),
      subjectClaim: provider.subjectClaim,
      claims: { ...provider.claims },
      issuer: provider.issuer ?? "",
      jwksUri: provider.jwksUri ?? "",
      tokenAuthMethod: provider.tokenAuthMethod,
      responseMode: provider.responseMode ?? "",
      teamId: provider.teamId ?? "",
      keyId: provider.keyId ?? "",
      idpEntityId: provider.idpEntityId ?? "",
      idpSsoUrl: provider.idpSsoUrl ?? "",
      idpCertificates: provider.idpCertificates ?? "",
      metadataUrl: provider.metadataUrl ?? "",
      nameIdFormat: provider.nameIdFormat ?? "",
      role: provider.role,
      trustsEmail: provider.trustsEmail,
      emailDomains: provider.emailDomains.join(" "),
      signupScopes: provider.signupScopes.join(" "),
      delegates: provider.delegates,
      delegatedScopes: provider.delegatedScopes.join(" "),
      delegationParams: pairs(provider.delegationParams),
      resourceUrl: provider.resourceUrl ?? "",
    };
    feedback.clear();
  }

  function close() {
    picking = false;
    editing = null;
    draft = null;
    feedback.clear();
  }

  const trimmed = (value) => value?.trim() || null;
  const words = (value) => value.split(/[\s,]+/).filter(Boolean);
  const pairs = (held) =>
    Object.entries(held ?? {})
      .map(([name, value]) => `${name}=${value}`)
      .join(" ");
  const params = (value) =>
    Object.fromEntries(
      words(value)
        .map((pair) => pair.split("="))
        .filter(([name, held]) => name && held !== undefined)
        .map(([name, ...rest]) => [name, rest.join("=")]),
    );

  function claims() {
    return Object.fromEntries(
      Object.entries(draft.claims)
        .map(([claim, path]) => [claim, path?.trim()])
        .filter(([, path]) => path),
    );
  }

  function variables() {
    const held = {
      key: draft.key.trim(),
      name: draft.name.trim(),
      role: draft.role,
      trustsEmail: saml ? false : draft.trustsEmail,
      emailDomains: words(draft.emailDomains),
      signupScopes: words(draft.signupScopes),
      clientSecret: trimmed(draft.clientSecret),
      privateKey: trimmed(draft.privateKey),
      delegates: saml ? false : mcp || draft.delegates,
      delegatedScopes: saml ? [] : words(draft.delegatedScopes),
      delegationParams: saml ? {} : params(draft.delegationParams),
    };

    if (fresh && !custom) {
      return {
        ...held,
        preset: draft.preset,
        presetValues: draft.asked,
        clientId: trimmed(draft.clientId),
        teamId: trimmed(draft.teamId),
        keyId: trimmed(draft.keyId),
        metadataUrl: trimmed(draft.metadataUrl),
        ...(saml ? metadataFields() : {}),
        ...(mcp ? { resourceUrl: trimmed(draft.resourceUrl) } : {}),
      };
    }

    return {
      ...held,
      protocol: draft.protocol,
      authorizationUrl: saml ? null : trimmed(draft.authorizationUrl),
      tokenUrl: saml ? null : trimmed(draft.tokenUrl),
      userinfoUrl: saml ? null : trimmed(draft.userinfoUrl),
      emailsUrl: oauth2 ? trimmed(draft.emailsUrl) : null,
      clientId: saml ? null : trimmed(draft.clientId),
      scopes: saml ? [] : words(draft.scopes),
      subjectClaim: draft.subjectClaim.trim(),
      claims: claims(),
      issuer: oidc ? trimmed(draft.issuer) : null,
      jwksUri: oidc ? trimmed(draft.jwksUri) : null,
      tokenAuthMethod: draft.tokenAuthMethod,
      responseMode: trimmed(draft.responseMode),
      teamId: signsSecret ? trimmed(draft.teamId) : null,
      keyId: signsSecret ? trimmed(draft.keyId) : null,
      metadataUrl: saml ? trimmed(draft.metadataUrl) : null,
      nameIdFormat: saml ? trimmed(draft.nameIdFormat) : null,
      resourceUrl: mcp ? trimmed(draft.resourceUrl) : null,
      ...(saml ? metadataFields() : { idpEntityId: null, idpSsoUrl: null, idpCertificates: null }),
    };
  }

  const metadataFields = () => ({
    idpEntityId: trimmed(draft.idpEntityId),
    idpSsoUrl: trimmed(draft.idpSsoUrl),
    idpCertificates: trimmed(draft.idpCertificates),
    nameIdFormat: trimmed(draft.nameIdFormat),
  });

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
  }

  async function readMetadata() {
    busy = true;

    const data = await feedback.attempt(
      () =>
        api.query(METADATA, {
          metadataUrl: trimmed(draft.metadataUrl),
          metadataXml: trimmed(draft.metadataXml),
        }),
      "Read the identity provider's entity, sign-in URL and certificates.",
    );

    busy = false;

    if (!data) return;

    Object.assign(draft, data.readSamlMetadata);
    draft.metadataXml = "";
  }

  async function save() {
    busy = true;

    const adding = fresh;
    const done = await feedback.attempt(
      () => api.query(adding ? CREATE : UPDATE, variables()),
      adding
        ? mcp
          ? `${draft.name} is registered, and applications can be let use it.`
          : `${draft.name} can sign actors in now.`
        : `${draft.name} saved.`,
    );

    busy = false;

    if (!done) return;

    close();

    await load();
  }

  async function act(mutation, provider, notice, question = null) {
    if (question && !confirm(question)) return;

    const done = await feedback.attempt(
      () =>
        api.query(`mutation Act($key: ID!) { ${mutation}(key: $key) { provider { key } } }`, {
          key: provider.key,
        }),
      notice,
    );

    if (done) await load();
  }

  const archive = (provider) =>
    act(
      "archiveProvider",
      provider,
      `${provider.name} is archived.`,
      `Archive ${provider.name}? Nobody can sign in with it until it is restored.`,
    );

  const restore = (provider) => act("restoreProvider", provider, `${provider.name} is back.`);

  const register = (provider) =>
    act(
      "registerProvider",
      provider,
      `masks registered itself with ${provider.name} again.`,
      `Register with ${provider.name} again? Everybody connected to it has to connect again.`,
    );

  function copy(value) {
    navigator.clipboard?.writeText(value);
    feedback.clear();
  }

  const needsSecret = $derived(
    !saml && !mcp && !signsSecret && (fresh ? (chosen?.needs ?? ["client_secret"]).includes("client_secret") : true),
  );

  const complete = $derived.by(() => {
    if (!draft?.key.trim() || !draft.name.trim()) return false;
    if (fresh && !custom) return (chosen?.asks ?? []).every((variable) => draft.asked[variable]?.trim());
    if (saml) return draft.idpEntityId.trim() && draft.idpSsoUrl.trim() && draft.idpCertificates.trim();
    if (mcp) return fresh ? draft.resourceUrl.trim() : true;

    return draft.clientId.trim() && draft.authorizationUrl.trim() && draft.tokenUrl.trim();
  });
</script>

<Page title="Providers">
  {#snippet actions()}
    <button type="button" class="btn btn-primary btn-sm" onclick={add}>Add provider</button>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if picking}
    <Section title="Add provider" lede="Pick who actors will sign in with. Anything not listed speaks one of the three at the end.">
      {#snippet actions()}
        <button type="button" class="btn btn-ghost btn-sm" onclick={close}>Cancel</button>
      {/snippet}

      <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
        {#each presets as preset (preset.key)}
          <button
            type="button"
            class="flex items-baseline justify-between gap-3 rounded-lg border border-base-300 px-3 py-2.5 text-left hover:border-primary"
            class:border-dashed={preset.custom}
            onclick={() => pick(preset)}
          >
            <span class="text-sm font-medium">{preset.name}</span>
            <span class="font-mono text-xs opacity-50">{preset.protocol}</span>
          </button>
        {/each}
      </div>
    </Section>
  {/if}

  {#if draft}
    <Section
      title={fresh ? `Add ${chosen?.custom ? PROTOCOLS[draft.protocol] : chosen?.name}` : `Edit ${draft.name}`}
      lede={chosen?.guide ? null : PROTOCOLS[draft.protocol]}
    >
      {#if chosen?.guide && fresh}
        <p class="text-sm opacity-70">
          Register masks with {chosen.name} first:
          <a class="link" href={chosen.guide} target="_blank" rel="noreferrer noopener">{chosen.name}'s console</a>.
        </p>
      {/if}

      <div class="flex flex-col gap-2 rounded-lg bg-base-200 p-3">
        <span class="legend">Give {draft.name.trim() || "the provider"} these</span>

        {#each saml ? [["Assertion consumer service URL", callbackUrl], ["Service provider entity ID", spEntityId]] : [["Redirect URI", callbackUrl]] as [label, value] (label)}
          <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
            <span class="text-xs opacity-60">{label}</span>
            <button type="button" class="link font-mono text-xs break-all" onclick={() => copy(value)}>
              {value}
            </button>
          </div>
        {/each}
      </div>

      <div class="grid gap-3 sm:grid-cols-2">
        <Field label="Name" bind:value={draft.name} placeholder="Acme" />
        <Field
          label="Key"
          bind:value={draft.key}
          disabled={!fresh}
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          placeholder="acme"
        />
      </div>

      {#if fresh && !custom && chosen.asks.length}
        <div class="grid gap-3 sm:grid-cols-2">
          {#each chosen.asks as variable (variable)}
            <Field
              label={ASKED[variable]?.[0] ?? variable}
              bind:value={draft.asked[variable]}
              placeholder={ASKED[variable]?.[1] ?? ""}
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
            />
          {/each}
        </div>
      {/if}

      {#if saml}
        <div class="flex flex-col gap-3">
          <span class="legend">Identity provider</span>

          <div class="flex flex-wrap items-end gap-3">
            <div class="min-w-64 flex-1">
              <Field
                label="Metadata URL"
                bind:value={draft.metadataUrl}
                placeholder="https://idp.acme.test/metadata"
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
              />
            </div>
            <button
              type="button"
              class="btn btn-sm"
              disabled={busy || !(draft.metadataUrl.trim() || draft.metadataXml.trim())}
              onclick={readMetadata}
            >
              Read
            </button>
          </div>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium opacity-70">Or paste the metadata</span>
            <textarea class="textarea textarea-sm w-full font-mono text-xs" rows="3" bind:value={draft.metadataXml}></textarea>
          </label>

          <p class="text-xs opacity-60">
            A metadata URL is read again every night, so a certificate the identity provider rotates is
            picked up without anybody noticing.
          </p>

          <div class="grid gap-3 sm:grid-cols-2">
            <Field label="Entity ID" bind:value={draft.idpEntityId} />
            <Field label="Sign-in URL" bind:value={draft.idpSsoUrl} />
          </div>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium opacity-70">Signing certificates</span>
            <textarea class="textarea textarea-sm w-full font-mono text-xs" rows="4" bind:value={draft.idpCertificates}></textarea>
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="text-xs font-medium opacity-70">Name ID format</span>
            <select class="select select-sm w-full" bind:value={draft.nameIdFormat}>
              {#each NAME_ID_FORMATS as [value, label] (value)}
                <option {value}>{label}</option>
              {/each}
            </select>
          </label>
        </div>
      {/if}

      {#if mcp}
        <div class="flex flex-col gap-2">
          {#if fresh && custom}
            <Field
              label="MCP server URL"
              bind:value={draft.resourceUrl}
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              placeholder="https://mcp.acme.test/mcp"
            />
          {:else}
            <span class="font-mono text-xs break-all opacity-70">{draft.resourceUrl}</span>
          {/if}
          <p class="text-xs opacity-60">
            masks finds the server's own authorization server from its protected resource metadata and
            registers itself there, so there is no client ID to copy. An MCP server never signs anybody in;
            it is only something applications can be let use.
          </p>
        </div>
      {/if}

      {#if custom && oidc}
        <div class="flex flex-wrap items-end gap-3">
          <div class="min-w-64 flex-1">
            <Field
              label="Issuer"
              bind:value={draft.issuer}
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              placeholder="https://id.acme.test"
            />
          </div>
          <button type="button" class="btn btn-sm" disabled={busy || !draft.issuer.trim()} onclick={discover}>
            Discover
          </button>
        </div>
      {/if}

      {#if custom && !saml && !mcp}
        <div class="grid gap-3 sm:grid-cols-2">
          <Field label="Authorization URL" bind:value={draft.authorizationUrl} />
          <Field label="Token URL" bind:value={draft.tokenUrl} />
          <Field label="Userinfo URL" bind:value={draft.userinfoUrl} placeholder={oauth2 ? "" : "optional"} />
          {#if oauth2}
            <Field label="Verified emails URL" bind:value={draft.emailsUrl} placeholder="optional" />
          {:else}
            <Field label="JWKS URI" bind:value={draft.jwksUri} placeholder="discovered if left empty" />
          {/if}
        </div>
      {/if}

      {#if !saml && !mcp}
        <div class="flex flex-col gap-3">
          <span class="legend">Credentials</span>

          <div class="grid gap-3 sm:grid-cols-2">
            <Field label={signsSecret ? "Services ID" : "Client ID"} bind:value={draft.clientId} autocomplete="off" />
            {#if needsSecret}
              <Field
                label="Client secret"
                type="password"
                bind:value={draft.clientSecret}
                autocomplete="off"
                placeholder={fresh ? "" : "unchanged"}
              />
            {/if}
          </div>

          {#if signsSecret}
            <div class="grid gap-3 sm:grid-cols-2">
              <Field label="Team ID" bind:value={draft.teamId} autocomplete="off" />
              <Field label="Key ID" bind:value={draft.keyId} autocomplete="off" />
            </div>

            <label class="flex flex-col gap-1.5">
              <span class="text-xs font-medium opacity-70">Private key (.p8)</span>
              <textarea
                class="textarea textarea-sm w-full font-mono text-xs"
                rows="4"
                bind:value={draft.privateKey}
                placeholder={fresh ? "-----BEGIN PRIVATE KEY-----" : "unchanged"}
              ></textarea>
            </label>
          {/if}

          {#if custom}
            <div class="grid gap-3 sm:grid-cols-2">
              <label class="flex flex-col gap-1.5">
                <span class="text-xs font-medium opacity-70">Sends the secret</span>
                <select class="select select-sm w-full" bind:value={draft.tokenAuthMethod}>
                  <option value="client_secret_post">in the request body</option>
                  <option value="client_secret_basic">as basic auth</option>
                  <option value="signed_secret">as a token it signs (Apple)</option>
                </select>
              </label>
              <Field
                label="Extra scopes"
                bind:value={draft.scopes}
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
                placeholder={oidc ? "openid email profile are always asked" : "read:user"}
              />
            </div>
          {/if}
        </div>
      {/if}

      {#if custom && !mcp}
        <details class="text-sm" open={oauth2 || saml}>
          <summary class="cursor-pointer opacity-70">Where each claim comes from</summary>

          <div class="grid gap-3 pt-3 sm:grid-cols-2">
            <Field
              label={saml ? "Subject (name_id, or an attribute)" : oidc ? "Subject (sub or oid)" : "Subject path"}
              bind:value={draft.subjectClaim}
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
            />
            {#each MAPPED.filter(([claim]) => !(saml && claim === "email_verified")) as [claim, label] (claim)}
              <Field
                {label}
                bind:value={draft.claims[claim]}
                placeholder={saml ? "attribute name" : claim}
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
              />
            {/each}
          </div>
        </details>
      {/if}

      {#if !saml}
        <div class="flex flex-col gap-3 rounded-lg bg-base-200 p-3">
          <span class="legend">Applications</span>

          {#if !mcp}
            <label class="flex items-start gap-3 text-sm">
              <input type="checkbox" class="toggle toggle-sm" bind:checked={draft.delegates} />
              <span>
                Let applications use somebody's {draft.name.trim() || "provider"} account
                <span class="block text-xs opacity-60">
                  An approved application can ask an actor to let it act as them at
                  {draft.name.trim() || "the provider"} while they are away. masks keeps the tokens, refreshes
                  them, and hands each one only to the application that actor said yes to.
                </span>
              </span>
            </label>
          {/if}

          {#if draft.delegates || mcp}
            <div class="grid gap-3 sm:grid-cols-2">
              <Field
                label="What applications may do"
                bind:value={draft.delegatedScopes}
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
                placeholder={mcp ? "whatever the server grants" : "https://www.googleapis.com/auth/drive.readonly"}
              />
              <Field
                label="Extra parameters when connecting"
                bind:value={draft.delegationParams}
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
                placeholder="access_type=offline prompt=consent"
              />
            </div>
            <p class="text-xs opacity-60">
              An application asks for <span class="font-mono">masks:delegate:{draft.key.trim() || "key"}</span>.
              Changing what applications may do asks everybody to connect again.
            </p>
          {/if}
        </div>
      {/if}

      {#if !mcp}
      <div class="flex flex-col gap-3 rounded-lg bg-base-200 p-3">
        <span class="legend">Signing in</span>

        <label class="flex items-start gap-3 text-sm">
          <input
            type="checkbox"
            class="toggle toggle-sm"
            checked={draft.role === "delegate"}
            onchange={(event) => (draft.role = event.currentTarget.checked ? "delegate" : "credential")}
          />
          <span>
            {draft.name.trim() || "This provider"} owns the account
            <span class="block text-xs opacity-60">
              On, somebody new gets an account here, and their name, photo and address follow
              {draft.name.trim() || "the provider"} each time they sign in. Off, it is only another way into
              an account that already exists. Either way it stands in for a password, never for a second
              factor.
            </span>
          </span>
        </label>

        {#if !saml}
          <label class="flex items-start gap-3 text-sm">
            <input type="checkbox" class="toggle toggle-sm" bind:checked={draft.trustsEmail} />
            <span>
              Trust the addresses it confirms
              <span class="block text-xs opacity-60">
                Only for a provider that really checks an actor holds the mailbox, as Google, Apple and
                GitHub do. Off, only addresses in the domains below are taken at its word.
              </span>
            </span>
          </label>
        {/if}

        <div class="grid gap-3 sm:grid-cols-2">
          <Field
            label={saml ? "Email domains it answers for" : "Email domains"}
            bind:value={draft.emailDomains}
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
            placeholder="any domain"
          />
          {#if draft.role === "delegate"}
            <Field
              label="Scopes a new account holds"
              bind:value={draft.signupScopes}
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              placeholder="openid profile email offline_access identities"
            />
          {/if}
        </div>
      </div>
      {/if}

      <div class="flex gap-2">
        <button type="button" class="btn btn-primary btn-sm" disabled={busy || !complete} onclick={save}>
          {busy ? "Saving..." : fresh ? "Add" : "Save"}
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onclick={close}>Cancel</button>
      </div>
    </Section>
  {/if}

  {#if loading && active.length === 0 && archived.length === 0}
    <Spinner />
  {:else if active.length === 0 && archived.length === 0 && !picking && !draft}
    <div class="rounded-box border border-base-300 bg-base-100 px-6 py-14 text-center">
      <p class="mx-auto max-w-sm text-sm opacity-70">
        No provider is set up. Add one and actors can sign in with Google, GitHub, their company's
        identity provider, or anything that speaks OpenID Connect, OAuth 2.0 or SAML.
      </p>
    </div>
  {:else}
    {#each active as provider (provider.key)}
      <Section title={provider.name} lede={provider.key}>
        {#snippet actions()}
          <button type="button" class="btn btn-sm" onclick={() => edit(provider)}>Edit</button>
          {#if provider.protocol === "mcp"}
            <button type="button" class="btn btn-sm" onclick={() => register(provider)}>Register again</button>
          {/if}
          <button type="button" class="btn btn-sm btn-error btn-outline" onclick={() => archive(provider)}>
            Archive
          </button>
        {/snippet}

        <div class="flex flex-wrap gap-2">
          <span class="badge badge-ghost badge-sm">{PROTOCOLS[provider.protocol]}</span>
          {#if provider.protocol === "mcp"}
            <span class="badge badge-ghost badge-sm">never signs in</span>
          {:else if provider.role === "delegate"}
            <span class="badge badge-warning badge-sm">owns accounts</span>
          {:else}
            <span class="badge badge-ghost badge-sm">existing accounts only</span>
          {/if}
          {#if provider.trustsEmail}
            <span class="badge badge-ghost badge-sm">trusts confirmed addresses</span>
          {/if}
          {#if provider.delegates}
            <span class="badge badge-info badge-sm">applications can use it</span>
          {/if}
          {#each provider.emailDomains as domain (domain)}
            <span class="badge badge-ghost badge-sm font-mono">@{domain}</span>
          {/each}
        </div>

        <dl class="grid gap-x-6 gap-y-2 text-sm sm:grid-cols-2">
          <div class="sm:col-span-2">
            <dt class="text-xs opacity-60">{provider.protocol === "saml" ? "Assertion consumer service URL" : "Redirect URI"}</dt>
            <dd>
              <button type="button" class="link font-mono text-xs break-all" onclick={() => copy(provider.callbackUrl)}>
                {provider.callbackUrl}
              </button>
            </dd>
          </div>

          {#if provider.protocol === "saml"}
            <div class="sm:col-span-2">
              <dt class="text-xs opacity-60">Service provider entity ID</dt>
              <dd>
                <a class="link font-mono text-xs break-all" href={provider.spEntityId} target="_blank" rel="noreferrer">
                  {provider.spEntityId}
                </a>
              </dd>
            </div>
            <div>
              <dt class="text-xs opacity-60">Identity provider</dt>
              <dd class="font-mono text-xs break-all">{provider.idpEntityId}</dd>
            </div>
            <div>
              <dt class="text-xs opacity-60">Metadata</dt>
              <dd class="text-xs">
                {#if provider.metadataUrl}
                  read {provider.metadataFetchedAt ? day(provider.metadataFetchedAt) : "never"}
                {:else}
                  pasted, not refreshed
                {/if}
              </dd>
            </div>
          {:else if provider.protocol !== "mcp"}
            <div>
              <dt class="text-xs opacity-60">Client ID</dt>
              <dd class="font-mono break-all">{provider.clientId}</dd>
            </div>
            <div>
              <dt class="text-xs opacity-60">{provider.tokenAuthMethod === "signed_secret" ? "Signing key" : "Secret"}</dt>
              <dd>
                {#if provider.tokenAuthMethod === "signed_secret" ? provider.privateKeyHeld : provider.secretHeld}
                  held
                {:else}
                  <span class="text-warning">none set</span>
                {/if}
              </dd>
            </div>
            {#if provider.issuer}
              <div>
                <dt class="text-xs opacity-60">Issuer</dt>
                <dd class="font-mono text-xs break-all">{provider.issuer}</dd>
              </div>
            {/if}
            <div>
              <dt class="text-xs opacity-60">Scopes asked upstream</dt>
              <dd class="font-mono text-xs break-all">{provider.scopes.join(" ") || "—"}</dd>
            </div>
          {/if}

          {#if provider.protocol === "mcp"}
            <div class="sm:col-span-2">
              <dt class="text-xs opacity-60">MCP server</dt>
              <dd class="font-mono text-xs break-all">{provider.resourceUrl}</dd>
            </div>
            <div>
              <dt class="text-xs opacity-60">Registered</dt>
              <dd class="text-xs">{provider.registeredAt ? day(provider.registeredAt) : "never"}</dd>
            </div>
          {/if}

          {#if provider.delegates}
            <div>
              <dt class="text-xs opacity-60">Applications ask for</dt>
              <dd class="font-mono text-xs break-all">{provider.delegationScope}</dd>
            </div>
            <div>
              <dt class="text-xs opacity-60">Applications using it</dt>
              <dd>{provider.delegations}</dd>
            </div>
            {#if provider.delegatedScopes.length}
              <div class="sm:col-span-2">
                <dt class="text-xs opacity-60">What applications may do</dt>
                <dd class="font-mono text-xs break-all">{provider.delegatedScopes.join(" ")}</dd>
              </div>
            {/if}
          {/if}

          <div>
            <dt class="text-xs opacity-60">Connected accounts</dt>
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
            <summary class="cursor-pointer opacity-70">Who is connected ({connectionsFor(provider).length})</summary>

            <div class="pt-3">
              <Connections {api} {feedback} rows={connectionsFor(provider)} onchange={load} showActor />
            </div>
          </details>
        {/if}
      </Section>
    {/each}

    {#if archived.length}
      <Section title="Archived">
        <ul class="flex flex-col gap-1.5">
          {#each archived as provider (provider.key)}
            <li class="slat">
              <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                <span class="flex flex-wrap items-baseline gap-2">
                  <span class="text-sm font-medium">{provider.name}</span>
                  <span class="font-mono text-xs opacity-50">{provider.key}</span>
                </span>

                <span class="flex items-baseline gap-3 text-xs">
                  <span class="opacity-60">archived {day(provider.archivedAt)}</span>
                  <button type="button" class="link" onclick={() => restore(provider)}>Restore</button>
                </span>
              </div>
            </li>
          {/each}
        </ul>
      </Section>
    {/if}
  {/if}
</Page>
