<script>
  import Connections from "./Connections.svelte";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import Empty from "./ui/Empty.svelte";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import { t } from "./lib/copy.js";

  let { api } = $props();

  const PROTOCOLS = Object.fromEntries(
    ["oidc", "oauth2", "saml", "mcp"].map((protocol) => [protocol, t(`providers.protocols.${protocol}`)]),
  );

  const MAPPED = ["email", "email_verified", "name", "given_name", "family_name", "preferred_username", "picture"].map(
    (claim) => [claim, t(`providers.claims.${claim}`)],
  );

  const NAME_ID_FORMATS = [
    ["", t("providers.name_id_formats.any")],
    ["urn:oasis:names:tc:SAML:2.0:nameid-format:persistent", t("providers.name_id_formats.persistent")],
    ["urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress", t("providers.name_id_formats.email")],
    ["urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified", t("providers.name_id_formats.unspecified")],
  ];

  const ASKED = {
    domain: [t("providers.asked.domain"), "acme.okta.com"],
    tenant: [t("providers.asked.tenant"), "00000000-0000-0000-0000-000000000000"],
    realm: [t("providers.asked.realm"), "staff"],
  };

  const FIELDS = `
    key name protocol preset authorizationUrl tokenUrl userinfoUrl emailsUrl clientId
    scopes authorizeParams subjectClaim claims tokenAuthMethod responseMode teamId keyId
    secretHeld privateKeyHeld connections signedIn archivedAt createdAt callbackUrl
    issuer jwksUri role trustsEmail receivesSignals emailDomains signupScopes
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
    ["receivesSignals", "Boolean"],
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
    receivesSignals: false,
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
      receivesSignals: provider.receivesSignals,
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
      receivesSignals: oidc ? draft.receivesSignals : false,
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
      t("providers.notices.discovered"),
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
      t("providers.notices.metadata_read"),
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
          ? t("providers.notices.registered", { name: draft.name })
          : t("providers.notices.added", { name: draft.name })
        : t("providers.notices.saved", { name: draft.name }),
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
      t("providers.notices.archived", { name: provider.name }),
      t("providers.confirm.archive", { name: provider.name }),
    );

  const restore = (provider) => act("restoreProvider", provider, t("providers.notices.restored", { name: provider.name }));

  const register = (provider) =>
    act(
      "registerProvider",
      provider,
      t("providers.notices.reregistered", { name: provider.name }),
      t("providers.confirm.register", { name: provider.name }),
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

<Page title={t("providers.title")}>
  {#snippet actions()}
    <button type="button" class="btn btn-primary btn-sm" onclick={add}>{t("providers.add")}</button>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if picking}
    <Section title={t("providers.add")} help={t("providers.picker.help")}>
      {#snippet actions()}
        <button type="button" class="btn btn-ghost btn-sm" onclick={close}>{t("providers.cancel")}</button>
      {/snippet}

      <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
        {#each presets as preset (preset.key)}
          <button
            type="button"
            class="flex items-baseline justify-between gap-3 sheet sheet-press px-3 py-2.5 text-left"
            onclick={() => pick(preset)}
          >
            <span class="text-sm font-medium">{preset.name}</span>
            <span class="font-mono text-xs opacity-75">{preset.protocol}</span>
          </button>
        {/each}
      </div>
    </Section>
  {/if}

  {#if draft}
    <Section
      title={fresh
        ? t("providers.form.add_title", { name: chosen?.custom ? PROTOCOLS[draft.protocol] : chosen?.name })
        : t("providers.form.edit_title", { name: draft.name })}
      lede={chosen?.guide ? null : PROTOCOLS[draft.protocol]}
    >
      {#if chosen?.guide && fresh}
        <p class="text-sm opacity-85">
          {t("providers.form.guide_lead", { name: chosen.name })}
          <a class="link" href={chosen.guide} target="_blank" rel="noreferrer noopener">{t("providers.form.guide_link", { name: chosen.name })}</a>.
        </p>
      {/if}

      <div class="flex flex-col gap-2 tray p-3">
        <span class="legend">{t("providers.form.give", { name: draft.name.trim() || t("providers.form.the_provider") })}</span>

        {#each saml ? [[t("providers.form.acs_url"), callbackUrl], [t("providers.form.sp_entity_id"), spEntityId]] : [[t("providers.form.redirect_uri"), callbackUrl]] as [label, value] (label)}
          <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
            <span class="hint">{label}</span>
            <button type="button" class="link font-mono text-xs break-all" onclick={() => copy(value)}>
              {value}
            </button>
          </div>
        {/each}
      </div>

      <div class="grid gap-3 sm:grid-cols-2">
        <Field label={t("providers.form.name")} bind:value={draft.name} placeholder="Acme" />
        <Field
          label={t("providers.form.key")}
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
          <span class="legend">{t("providers.form.identity_provider")}</span>

          <div class="flex flex-wrap items-end gap-3">
            <div class="min-w-64 flex-1">
              <Field
                label={t("providers.form.metadata_url")}
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
              {t("providers.form.read")}
            </button>
          </div>

          <label class="flex flex-col gap-1.5">
            <span class="field-label">{t("providers.form.paste_metadata")}</span>
            <textarea class="textarea textarea-sm w-full font-mono text-xs" rows="3" bind:value={draft.metadataXml}></textarea>
          </label>

          <p class="hint">
            {t("providers.form.metadata_hint")}
          </p>

          <div class="grid gap-3 sm:grid-cols-2">
            <Field label={t("providers.form.entity_id")} bind:value={draft.idpEntityId} />
            <Field label={t("providers.form.sign_in_url")} bind:value={draft.idpSsoUrl} />
          </div>

          <label class="flex flex-col gap-1.5">
            <span class="field-label">{t("providers.form.certificates")}</span>
            <textarea class="textarea textarea-sm w-full font-mono text-xs" rows="4" bind:value={draft.idpCertificates}></textarea>
          </label>

          <label class="flex flex-col gap-1.5">
            <span class="field-label">{t("providers.form.name_id_format")}</span>
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
              label={t("providers.form.mcp_url")}
              bind:value={draft.resourceUrl}
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              placeholder="https://mcp.acme.test/mcp"
            />
          {:else}
            <span class="font-mono text-xs break-all opacity-85">{draft.resourceUrl}</span>
          {/if}
          <p class="hint">
            {t("providers.form.mcp_hint")}
          </p>
        </div>
      {/if}

      {#if custom && oidc}
        <div class="flex flex-wrap items-end gap-3">
          <div class="min-w-64 flex-1">
            <Field
              label={t("providers.form.issuer")}
              bind:value={draft.issuer}
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              placeholder="https://id.acme.test"
            />
          </div>
          <button type="button" class="btn btn-sm" disabled={busy || !draft.issuer.trim()} onclick={discover}>
            {t("providers.form.discover")}
          </button>
        </div>
      {/if}

      {#if custom && !saml && !mcp}
        <div class="grid gap-3 sm:grid-cols-2">
          <Field label={t("providers.form.authorization_url")} bind:value={draft.authorizationUrl} />
          <Field label={t("providers.form.token_url")} bind:value={draft.tokenUrl} />
          <Field
            label={t("providers.form.userinfo_url")}
            bind:value={draft.userinfoUrl}
            placeholder={oauth2 ? "" : t("providers.form.optional")}
          />
          {#if oauth2}
            <Field label={t("providers.form.emails_url")} bind:value={draft.emailsUrl} placeholder={t("providers.form.optional")} />
          {:else}
            <Field
              label={t("providers.form.jwks_uri")}
              bind:value={draft.jwksUri}
              placeholder={t("providers.form.discovered_if_empty")}
            />
          {/if}
        </div>
      {/if}

      {#if !saml && !mcp}
        <div class="flex flex-col gap-3">
          <span class="legend">{t("providers.form.credentials")}</span>

          <div class="grid gap-3 sm:grid-cols-2">
            <Field
              label={signsSecret ? t("providers.form.services_id") : t("providers.form.client_id")}
              bind:value={draft.clientId}
              autocomplete="off"
            />
            {#if needsSecret}
              <Field
                label={t("providers.form.client_secret")}
                type="password"
                bind:value={draft.clientSecret}
                autocomplete="off"
                placeholder={fresh ? "" : t("providers.form.unchanged")}
              />
            {/if}
          </div>

          {#if signsSecret}
            <div class="grid gap-3 sm:grid-cols-2">
              <Field label={t("providers.form.team_id")} bind:value={draft.teamId} autocomplete="off" />
              <Field label={t("providers.form.key_id")} bind:value={draft.keyId} autocomplete="off" />
            </div>

            <label class="flex flex-col gap-1.5">
              <span class="field-label">{t("providers.form.private_key")}</span>
              <textarea
                class="textarea textarea-sm w-full font-mono text-xs"
                rows="4"
                bind:value={draft.privateKey}
                placeholder={fresh ? "-----BEGIN PRIVATE KEY-----" : t("providers.form.unchanged")}
              ></textarea>
            </label>
          {/if}

          {#if custom}
            <div class="grid gap-3 sm:grid-cols-2">
              <label class="flex flex-col gap-1.5">
                <span class="field-label">{t("providers.form.sends_secret")}</span>
                <select class="select select-sm w-full" bind:value={draft.tokenAuthMethod}>
                  <option value="client_secret_post">{t("providers.form.secret_post")}</option>
                  <option value="client_secret_basic">{t("providers.form.secret_basic")}</option>
                  <option value="signed_secret">{t("providers.form.secret_signed")}</option>
                </select>
              </label>
              <Field
                label={t("providers.form.extra_scopes")}
                bind:value={draft.scopes}
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
                placeholder={oidc ? t("providers.form.oidc_scopes") : "read:user"}
              />
            </div>
          {/if}
        </div>
      {/if}

      {#if custom && !mcp}
        <details class="text-sm" open={oauth2 || saml}>
          <summary class="cursor-pointer opacity-85">{t("providers.form.claims")}</summary>

          <div class="grid gap-3 pt-3 sm:grid-cols-2">
            <Field
              label={saml
                ? t("providers.form.subject_saml")
                : oidc
                  ? t("providers.form.subject_oidc")
                  : t("providers.form.subject_path")}
              bind:value={draft.subjectClaim}
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
            />
            {#each MAPPED.filter(([claim]) => !(saml && claim === "email_verified")) as [claim, label] (claim)}
              <Field
                {label}
                bind:value={draft.claims[claim]}
                placeholder={saml ? t("providers.form.attribute_name") : claim}
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
              />
            {/each}
          </div>
        </details>
      {/if}

      {#if !saml}
        <div class="flex flex-col gap-3 tray p-3">
          <span class="legend">{t("providers.form.applications")}</span>

          {#if !mcp}
            <label class="flex items-start gap-3 text-sm">
              <input type="checkbox" class="toggle toggle-sm" bind:checked={draft.delegates} />
              <span>
                {t("providers.form.delegates", { name: draft.name.trim() || t("providers.form.provider") })}
                <span class="hint block">
                  {t("providers.form.delegates_hint", { name: draft.name.trim() || t("providers.form.the_provider") })}
                </span>
              </span>
            </label>
          {/if}

          {#if draft.delegates || mcp}
            <div class="grid gap-3 sm:grid-cols-2">
              <Field
                label={t("providers.form.delegated_scopes")}
                bind:value={draft.delegatedScopes}
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
                placeholder={mcp ? t("providers.form.server_grants") : "https://www.googleapis.com/auth/drive.readonly"}
              />
              <Field
                label={t("providers.form.delegation_params")}
                bind:value={draft.delegationParams}
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
                placeholder="access_type=offline prompt=consent"
              />
            </div>
            <p class="hint">
              {t("providers.form.delegation_asks")}
              <span class="font-mono">masks:delegate:{draft.key.trim() || "key"}</span>.
              {t("providers.form.delegation_reconnect")}
            </p>
          {/if}
        </div>
      {/if}

      {#if !mcp}
      <div class="flex flex-col gap-3 tray p-3">
        <span class="legend">{t("providers.form.signing_in")}</span>

        <label class="flex items-start gap-3 text-sm">
          <input
            type="checkbox"
            class="toggle toggle-sm"
            checked={draft.role === "delegate"}
            onchange={(event) => (draft.role = event.currentTarget.checked ? "delegate" : "credential")}
          />
          <span>
            {t("providers.form.owns", { name: draft.name.trim() || t("providers.form.this_provider") })}
            <span class="hint block">
              {t("providers.form.owns_hint", { name: draft.name.trim() || t("providers.form.the_provider") })}
            </span>
          </span>
        </label>

        {#if !saml}
          <label class="flex items-start gap-3 text-sm">
            <input type="checkbox" class="toggle toggle-sm" bind:checked={draft.trustsEmail} />
            <span>
              {t("providers.form.trusts_email")}
              <span class="hint block">
                {t("providers.form.trusts_email_hint")}
              </span>
            </span>
          </label>
        {/if}

        {#if oidc}
          <label class="flex items-start gap-3 text-sm">
            <input type="checkbox" class="toggle toggle-sm" bind:checked={draft.receivesSignals} />
            <span>
              {t("providers.form.signals")}
              <span class="hint block">
                {t("providers.form.signals_lead")} <code>{origin}/ssf/events</code>.
                {t("providers.form.signals_rest")}
              </span>
            </span>
          </label>
        {/if}

        <div class="grid gap-3 sm:grid-cols-2">
          <Field
            label={saml ? t("providers.form.saml_domains") : t("providers.form.domains")}
            bind:value={draft.emailDomains}
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
            placeholder={t("providers.form.any_domain")}
          />
          {#if draft.role === "delegate"}
            <Field
              label={t("providers.form.signup_scopes")}
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
          {busy ? t("providers.form.saving") : fresh ? t("providers.form.add") : t("providers.form.save")}
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onclick={close}>{t("providers.cancel")}</button>
      </div>
    </Section>
  {/if}

  {#if loading && active.length === 0 && archived.length === 0}
    <Spinner />
  {:else if active.length === 0 && archived.length === 0 && !picking && !draft}
    <Empty>
      {t("providers.empty")}
    </Empty>
  {:else}
    {#each active as provider (provider.key)}
      <Section title={provider.name} lede={provider.key}>
        {#snippet actions()}
          <button type="button" class="btn btn-sm" onclick={() => edit(provider)}>{t("providers.edit")}</button>
          {#if provider.protocol === "mcp"}
            <button type="button" class="btn btn-sm" onclick={() => register(provider)}>{t("providers.register")}</button>
          {/if}
          <button type="button" class="btn btn-sm btn-error btn-outline" onclick={() => archive(provider)}>
            {t("providers.archive")}
          </button>
        {/snippet}

        <div class="flex flex-wrap gap-2">
          <span class="badge badge-ghost badge-sm">{PROTOCOLS[provider.protocol]}</span>
          {#if provider.protocol === "mcp"}
            <span class="badge badge-ghost badge-sm">{t("providers.badges.never_signs_in")}</span>
          {:else if provider.role === "delegate"}
            <span class="badge badge-warning badge-sm">{t("providers.badges.owns_accounts")}</span>
          {:else}
            <span class="badge badge-ghost badge-sm">{t("providers.badges.existing_only")}</span>
          {/if}
          {#if provider.trustsEmail}
            <span class="badge badge-ghost badge-sm">{t("providers.badges.trusts_email")}</span>
          {/if}
          {#if provider.receivesSignals}
            <span class="badge badge-ghost badge-sm">{t("providers.badges.signals")}</span>
          {/if}
          {#if provider.delegates}
            <span class="badge badge-info badge-sm">{t("providers.badges.delegates")}</span>
          {/if}
          {#each provider.emailDomains as domain (domain)}
            <span class="badge badge-ghost badge-sm font-mono">@{domain}</span>
          {/each}
        </div>

        <dl class="grid gap-x-6 gap-y-2 text-sm sm:grid-cols-2">
          <div class="sm:col-span-2">
            <dt class="term">
              {provider.protocol === "saml" ? t("providers.facts.acs_url") : t("providers.facts.redirect_uri")}
            </dt>
            <dd>
              <button type="button" class="link font-mono text-xs break-all" onclick={() => copy(provider.callbackUrl)}>
                {provider.callbackUrl}
              </button>
            </dd>
          </div>

          {#if provider.protocol === "saml"}
            <div class="sm:col-span-2">
              <dt class="term">{t("providers.facts.sp_entity_id")}</dt>
              <dd>
                <a class="link font-mono text-xs break-all" href={provider.spEntityId} target="_blank" rel="noreferrer">
                  {provider.spEntityId}
                </a>
              </dd>
            </div>
            <div>
              <dt class="term">{t("providers.facts.identity_provider")}</dt>
              <dd class="font-mono text-xs break-all">{provider.idpEntityId}</dd>
            </div>
            <div>
              <dt class="term">{t("providers.facts.metadata")}</dt>
              <dd class="text-xs">
                {#if provider.metadataUrl}
                  {t("providers.facts.metadata_read", {
                    day: provider.metadataFetchedAt ? day(provider.metadataFetchedAt) : t("providers.facts.never"),
                  })}
                {:else}
                  {t("providers.facts.pasted")}
                {/if}
              </dd>
            </div>
          {:else if provider.protocol !== "mcp"}
            <div>
              <dt class="term">{t("providers.facts.client_id")}</dt>
              <dd class="font-mono break-all">{provider.clientId}</dd>
            </div>
            <div>
              <dt class="term">
                {provider.tokenAuthMethod === "signed_secret" ? t("providers.facts.signing_key") : t("providers.facts.secret")}
              </dt>
              <dd>
                {#if provider.tokenAuthMethod === "signed_secret" ? provider.privateKeyHeld : provider.secretHeld}
                  {t("providers.facts.held")}
                {:else}
                  <span class="text-warning">{t("providers.facts.none_set")}</span>
                {/if}
              </dd>
            </div>
            {#if provider.issuer}
              <div>
                <dt class="term">{t("providers.facts.issuer")}</dt>
                <dd class="font-mono text-xs break-all">{provider.issuer}</dd>
              </div>
            {/if}
            <div>
              <dt class="term">{t("providers.facts.scopes")}</dt>
              <dd class="font-mono text-xs break-all">{provider.scopes.join(" ") || "—"}</dd>
            </div>
          {/if}

          {#if provider.protocol === "mcp"}
            <div class="sm:col-span-2">
              <dt class="term">{t("providers.facts.mcp_server")}</dt>
              <dd class="font-mono text-xs break-all">{provider.resourceUrl}</dd>
            </div>
            <div>
              <dt class="term">{t("providers.facts.registered")}</dt>
              <dd class="text-xs">{provider.registeredAt ? day(provider.registeredAt) : t("providers.facts.never")}</dd>
            </div>
          {/if}

          {#if provider.delegates}
            <div>
              <dt class="term">{t("providers.facts.delegation_scope")}</dt>
              <dd class="font-mono text-xs break-all">{provider.delegationScope}</dd>
            </div>
            <div>
              <dt class="term">{t("providers.facts.delegations")}</dt>
              <dd>{provider.delegations}</dd>
            </div>
            {#if provider.delegatedScopes.length}
              <div class="sm:col-span-2">
                <dt class="term">{t("providers.facts.delegated_scopes")}</dt>
                <dd class="font-mono text-xs break-all">{provider.delegatedScopes.join(" ")}</dd>
              </div>
            {/if}
          {/if}

          <div>
            <dt class="term">{t("providers.facts.connections")}</dt>
            <dd>
              {provider.connections}
              {#if provider.signedIn}
                <span class="hint">· {t("providers.facts.signed_in", { count: provider.signedIn })}</span>
              {/if}
            </dd>
          </div>
        </dl>

        {#if connectionsFor(provider).length}
          <details class="text-sm">
            <summary class="cursor-pointer opacity-85">
              {t("providers.connected", { count: connectionsFor(provider).length })}
            </summary>

            <div class="pt-3">
              <Connections {api} {feedback} rows={connectionsFor(provider)} onchange={load} showActor />
            </div>
          </details>
        {/if}
      </Section>
    {/each}

    {#if archived.length}
      <Section title={t("providers.archived")}>
        <ul class="slats">
          {#each archived as provider (provider.key)}
            <li class="slat">
              <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                <span class="flex flex-wrap items-baseline gap-2">
                  <span class="text-sm font-medium">{provider.name}</span>
                  <span class="font-mono text-xs opacity-75">{provider.key}</span>
                </span>

                <span class="flex items-baseline gap-3 text-xs">
                  <span class="opacity-80">{t("providers.archived_on", { day: day(provider.archivedAt) })}</span>
                  <button type="button" class="link" onclick={() => restore(provider)}>{t("providers.restore")}</button>
                </span>
              </div>
            </li>
          {/each}
        </ul>
      </Section>
    {/if}
  {/if}
</Page>
