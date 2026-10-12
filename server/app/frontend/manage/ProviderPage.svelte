<script>
  import { untrack } from "svelte";
  import Connections from "./Connections.svelte";
  import { t } from "./lib/copy.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import { protocolName, providerMarks, secretMissing } from "./lib/providers.js";
  import { useRouter } from "./lib/router.svelte.js";
  import Field from "./ui/Field.svelte";
  import Link from "./ui/Link.svelte";
  import Marks from "./ui/Marks.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Parts from "./ui/Parts.svelte";
  import Section from "./ui/Section.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api, providerKey, part = null } = $props();

  const router = useRouter();

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
    scopes subjectClaim claims tokenAuthMethod responseMode teamId keyId
    secretHeld privateKeyHeld connections signedIn archivedAt createdAt callbackUrl
    issuer jwksUri role trustsEmail receivesSignals emailDomains signupScopes
    idpEntityId idpSsoUrl idpCertificates metadataUrl metadataFetchedAt nameIdFormat spEntityId
    delegates delegatedScopes delegationParams delegationScope resourceUrl registeredAt delegations
    organization { key name }
  `;

  const PRESETS = `providerPresets { key name protocol asks needs defaults guide custom trustsEmail delegates delegatedScopes }`;

  const QUERY = `
    query Provider($key: ID!) {
      provider(key: $key) { ${FIELDS} }
      connections(provider: $key) {
        id subject label email emailVerified connectedAt signedInAt delegable
        provider { key name }
        actor { uuid identifier }
        delegations { id releasedAt client { clientId name } }
      }
      ${PRESETS}
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

  const declared = (extra) => [...extra, ...ARGUMENTS].map(([name, type]) => `$${name}: ${type}`).join(", ");
  const passed = (extra) => [...extra, ...ARGUMENTS].map(([name]) => `${name}: $${name}`).join(", ");

  const CREATE_EXTRA = [
    ["key", "ID!"],
    ["preset", "ID"],
    ["presetValues", "JSON"],
  ];

  const CREATE = `
    mutation Create(${declared(CREATE_EXTRA).replace("$name: String", "$name: String!")}) {
      createProvider(${passed(CREATE_EXTRA)}) { provider { key } }
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
      readSamlMetadata(metadataUrl: $metadataUrl, metadataXml: $metadataXml) { idpEntityId idpSsoUrl idpCertificates }
    }
  `;

  const pairs = (held) =>
    Object.entries(held ?? {})
      .map(([name, value]) => `${name}=${value}`)
      .join(" ");

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
    claims: Object.fromEntries(MAPPED.map(([claim]) => [claim, ""])),
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

  const drafted = (provider) => ({
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
    claims: { ...Object.fromEntries(MAPPED.map(([claim]) => [claim, ""])), ...provider.claims },
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
  });

  const feedback = createFeedback();

  let provider = $state(null);
  let connected = $state([]);
  let presets = $state([]);
  let draft = $state(null);
  let baseline = $state("");
  let loading = $state(true);
  let busy = $state(false);

  const fresh = $derived(providerKey === "new");
  const chosen = $derived(
    fresh ? (presets.find((preset) => preset.key === part) ?? null) : (presets.find((preset) => preset.key === provider?.preset) ?? null),
  );
  const custom = $derived(fresh ? Boolean(chosen?.custom) : true);
  const saml = $derived(draft?.protocol === "saml");
  const oauth2 = $derived(draft?.protocol === "oauth2");
  const oidc = $derived(draft?.protocol === "oidc");
  const mcp = $derived(draft?.protocol === "mcp");
  const signsSecret = $derived(draft?.tokenAuthMethod === "signed_secret");
  const origin = typeof window === "undefined" ? "" : window.location.origin;
  const callbackUrl = $derived(`${origin}/login/provider/${draft?.key?.trim() || "…"}/callback`);
  const spEntityId = $derived(`${origin}/login/provider/${draft?.key?.trim() || "…"}/metadata`);
  const named = $derived(draft?.name.trim() || t("providers.form.the_provider"));
  const dirty = $derived(Boolean(draft && !fresh && JSON.stringify(draft) !== baseline));

  const PARTS = $derived(
    [
      [null, "", t("providers.parts.setup")],
      !mcp && ["sign-in", "/sign-in", t("providers.parts.sign_in")],
      !saml && ["clients", "/clients", t("providers.parts.clients")],
      ["accounts", "/accounts", t("providers.parts.accounts", { count: connected.length })],
    ].filter(Boolean),
  );

  const known = $derived(presets.filter((preset) => !preset.custom));
  const generic = $derived(presets.filter((preset) => preset.custom));

  async function load() {
    loading = true;

    const data = await feedback.attempt(() =>
      fresh ? api.query(`query Presets { ${PRESETS} }`) : api.query(QUERY, { key: providerKey }),
    );

    loading = false;

    if (!data) return;

    presets = data.providerPresets;

    if (fresh) {
      provider = null;
      connected = [];
      return;
    }

    provider = data.provider;
    connected = data.connections;
    draft = provider ? drafted(provider) : null;
    baseline = JSON.stringify(draft);
  }

  $effect(() => {
    providerKey;
    untrack(load);
  });

  $effect(() => {
    if (!fresh) return;

    const preset = chosen;

    untrack(() => {
      draft = preset ? blank(preset) : null;
    });
  });

  const trimmed = (value) => value?.trim() || null;
  const words = (value) => value.split(/[\s,]+/).filter(Boolean);
  const params = (value) =>
    Object.fromEntries(
      words(value)
        .map((pair) => pair.split("="))
        .filter(([name, held]) => name && held !== undefined)
        .map(([name, ...rest]) => [name, rest.join("=")]),
    );

  const claims = () =>
    Object.fromEntries(
      Object.entries(draft.claims)
        .map(([claim, path]) => [claim, path?.trim()])
        .filter(([, path]) => path),
    );

  const metadataFields = () => ({
    idpEntityId: trimmed(draft.idpEntityId),
    idpSsoUrl: trimmed(draft.idpSsoUrl),
    idpCertificates: trimmed(draft.idpCertificates),
    nameIdFormat: trimmed(draft.nameIdFormat),
  });

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
      () => api.query(METADATA, { metadataUrl: trimmed(draft.metadataUrl), metadataXml: trimmed(draft.metadataXml) }),
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
    const key = draft.key.trim();
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

    if (adding) router.go(`/providers/${key}`);
    else await load();
  }

  const discard = () => {
    draft = JSON.parse(baseline);
  };

  async function act(mutation, notice, question = null) {
    if (question && !confirm(question)) return;

    const done = await feedback.attempt(
      () => api.query(`mutation Act($key: ID!) { ${mutation}(key: $key) { provider { key } } }`, { key: provider.key }),
      notice,
    );

    if (done) await load();
  }

  const archive = () =>
    act(
      "archiveProvider",
      t("providers.notices.archived", { name: provider.name }),
      t("providers.confirm.archive", { name: provider.name }),
    );

  const restore = () => act("restoreProvider", t("providers.notices.restored", { name: provider.name }));

  const register = () =>
    act(
      "registerProvider",
      t("providers.notices.reregistered", { name: provider.name }),
      t("providers.confirm.register", { name: provider.name }),
    );

  const copy = (value) => navigator.clipboard?.writeText(value);

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

  const lede = $derived(
    provider
      ? [
          protocolName(provider.protocol),
          provider.protocol === "mcp"
            ? t("providers.roles.never")
            : provider.role === "delegate"
              ? t("providers.roles.owns")
              : t("providers.roles.existing"),
        ].join(" · ")
      : null,
  );
</script>

{#snippet toggle(checked, onchange, label, hint)}
  <label class="flex items-start gap-3 text-sm">
    <input type="checkbox" class="toggle toggle-sm mt-0.5" {checked} onchange={(event) => onchange(event.currentTarget.checked)} />
    <span class="flex flex-col gap-0.5">
      <span>{label}</span>
      {#if hint}<span class="hint">{hint}</span>{/if}
    </span>
  </label>
{/snippet}

{#snippet give()}
  <Section row title={t("providers.form.give", { name: named })} lede={chosen?.guide && fresh ? null : t("providers.sections.give_lede")}>
    {#if chosen?.guide && fresh}
      <p class="text-sm">
        {t("providers.form.guide_lead", { name: chosen.name })}
        <a class="link" href={chosen.guide} target="_blank" rel="noreferrer noopener">{t("providers.form.guide_link", { name: chosen.name })}</a>.
      </p>
    {/if}

    <ul class="slats">
      {#each saml ? [[t("providers.form.acs_url"), callbackUrl], [t("providers.form.sp_entity_id"), spEntityId]] : [[t("providers.form.redirect_uri"), callbackUrl]] as [label, value] (label)}
        <li class="slat">
          <span class="hint text-xs">{label}</span>
          <span class="flex items-center justify-between gap-3">
            <code class="min-w-0 font-mono text-xs break-all">{value}</code>
            <button type="button" class="btn btn-ghost btn-xs shrink-0" onclick={() => copy(value)}>{t("providers.copy")}</button>
          </span>
        </li>
      {/each}
    </ul>
  </Section>
{/snippet}

{#snippet setup()}
  {@render give()}

  <Section row title={t("providers.sections.identity")} lede={t("providers.sections.identity_lede")}>
    <Field label={t("providers.form.name")} bind:value={draft.name} placeholder="Acme" />
    {#if fresh}
      <Field
        label={t("providers.form.key")}
        bind:value={draft.key}
        autocapitalize="none"
        autocorrect="off"
        spellcheck="false"
        placeholder="acme"
      />
    {/if}

    {#if fresh && !custom}
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
    {/if}
  </Section>

  {#if saml}
    <Section row title={t("providers.form.identity_provider")} lede={t("providers.form.metadata_hint")}>
      <Field
        label={t("providers.form.metadata_url")}
        bind:value={draft.metadataUrl}
        onsave={() => (draft.metadataUrl.trim() || draft.metadataXml.trim()) && !busy && readMetadata()}
        save={t("providers.form.read")}
        placeholder="https://idp.acme.test/metadata"
        autocapitalize="none"
        autocorrect="off"
        spellcheck="false"
      />

      {#if provider?.metadataUrl}
        <p class="hint">
          {t("providers.facts.metadata_read", {
            day: provider.metadataFetchedAt ? day(provider.metadataFetchedAt) : t("providers.facts.never"),
          })}
        </p>
      {/if}

      <label class="flex flex-col gap-1.5">
        <span class="field-label">{t("providers.form.paste_metadata")}</span>
        <textarea class="textarea textarea-sm w-full max-w-sm font-mono text-xs" rows="3" bind:value={draft.metadataXml}></textarea>
      </label>

      <Field label={t("providers.form.entity_id")} bind:value={draft.idpEntityId} />
      <Field label={t("providers.form.sign_in_url")} bind:value={draft.idpSsoUrl} />

      <label class="flex flex-col gap-1.5">
        <span class="field-label">{t("providers.form.certificates")}</span>
        <textarea class="textarea textarea-sm w-full max-w-sm font-mono text-xs" rows="4" bind:value={draft.idpCertificates}></textarea>
      </label>

      <label class="flex flex-col gap-1.5">
        <span class="field-label">{t("providers.form.name_id_format")}</span>
        <select class="select select-sm w-full" bind:value={draft.nameIdFormat}>
          {#each NAME_ID_FORMATS as [value, label] (value)}
            <option {value}>{label}</option>
          {/each}
        </select>
      </label>
    </Section>
  {/if}

  {#if mcp}
    <Section row title={t("providers.sections.mcp")} lede={t("providers.form.mcp_hint")}>
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
        <code class="font-mono text-xs break-all">{draft.resourceUrl}</code>
        {#if provider}
          <p class="hint">
            {t("providers.facts.registered", {
              day: provider.registeredAt ? day(provider.registeredAt) : t("providers.facts.never"),
            })}
          </p>
        {/if}
      {/if}
    </Section>
  {/if}

  {#if custom && !saml && !mcp}
    <Section row title={t("providers.sections.endpoints")} lede={oidc ? t("providers.sections.endpoints_oidc") : null}>
      {#if oidc}
        <Field
          label={t("providers.form.issuer")}
          bind:value={draft.issuer}
          onsave={() => draft.issuer.trim() && !busy && discover()}
          save={t("providers.form.discover")}
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          placeholder="https://id.acme.test"
        />
      {/if}

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
        <Field label={t("providers.form.jwks_uri")} bind:value={draft.jwksUri} placeholder={t("providers.form.discovered_if_empty")} />
      {/if}
    </Section>
  {/if}

  {#if !saml && !mcp}
    <Section row title={t("providers.form.credentials")} lede={t("providers.sections.credentials_lede", { name: named })}>
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
          placeholder={fresh ? "" : provider?.secretHeld ? t("providers.form.unchanged") : ""}
        />
      {/if}

      {#if signsSecret}
        <Field label={t("providers.form.team_id")} bind:value={draft.teamId} autocomplete="off" />
        <Field label={t("providers.form.key_id")} bind:value={draft.keyId} autocomplete="off" />

        <label class="flex flex-col gap-1.5">
          <span class="field-label">{t("providers.form.private_key")}</span>
          <textarea
            class="textarea textarea-sm w-full max-w-sm font-mono text-xs"
            rows="4"
            bind:value={draft.privateKey}
            placeholder={fresh ? "-----BEGIN PRIVATE KEY-----" : t("providers.form.unchanged")}
          ></textarea>
        </label>
      {/if}

      {#if custom}
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
      {/if}
    </Section>
  {/if}
{/snippet}

{#snippet signIn()}
  <Section row title={t("providers.sections.accounts")} lede={t("providers.form.owns_hint", { name: named })}>
    {@render toggle(
      draft.role === "delegate",
      (on) => (draft.role = on ? "delegate" : "credential"),
      t("providers.form.owns", { name: named }),
      null,
    )}

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
  </Section>

  <Section row title={t("providers.sections.addresses")}>
    {#if !saml}
      {@render toggle(draft.trustsEmail, (on) => (draft.trustsEmail = on), t("providers.form.trusts_email"), t("providers.form.trusts_email_hint"))}
    {/if}

    <Field
      label={saml ? t("providers.form.saml_domains") : t("providers.form.domains")}
      bind:value={draft.emailDomains}
      autocapitalize="none"
      autocorrect="off"
      spellcheck="false"
      placeholder={t("providers.form.any_domain")}
    />
  </Section>

  {#if oidc}
    <Section row title={t("providers.sections.signals")}>
      {@render toggle(
        draft.receivesSignals,
        (on) => (draft.receivesSignals = on),
        t("providers.form.signals"),
        `${t("providers.form.signals_lead")} ${origin}/ssf/events. ${t("providers.form.signals_rest")}`,
      )}
    </Section>
  {/if}

  {#if custom}
    <Section row title={t("providers.form.claims")} lede={t("providers.sections.claims_lede")}>
      <Field
        label={saml ? t("providers.form.subject_saml") : oidc ? t("providers.form.subject_oidc") : t("providers.form.subject_path")}
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
    </Section>
  {/if}
{/snippet}

{#snippet clients()}
  <Section row title={t("providers.sections.delegation")} lede={t("providers.form.delegates_hint", { name: named })}>
    {#if !mcp}
      {@render toggle(draft.delegates, (on) => (draft.delegates = on), t("providers.form.delegates", { name: named }), null)}
    {/if}

    {#if draft.delegates || mcp}
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
      <p class="hint">
        {t("providers.form.delegation_asks")}
        <code class="font-mono">masks:delegate:{draft.key.trim() || "key"}</code>.
        {t("providers.form.delegation_reconnect")}
      </p>
      {#if provider}
        <p class="text-sm">{t("providers.facts.delegations_count", { count: provider.delegations })}</p>
      {/if}
    {/if}
  </Section>
{/snippet}

{#if fresh}
  <Page
    title={chosen ? t("providers.form.add_title", { name: chosen.custom ? protocolName(chosen.protocol) : chosen.name }) : t("providers.add")}
    back={{ to: chosen ? "/providers/new" : "/providers", label: chosen ? t("providers.picker.back") : t("providers.back") }}
    lede={chosen ? null : t("providers.picker.help")}
  >
    <Notices feedback={feedback.state} />

    {#if loading}
      <Spinner />
    {:else if !chosen}
      {#each [[t("providers.picker.known"), known], [t("providers.picker.generic"), generic]] as [heading, list] (heading)}
        {#if list.length}
          <Section title={heading}>
            <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {#each list as preset (preset.key)}
                <Link to={`/providers/new/${preset.key}`} class="sheet sheet-press flex items-baseline justify-between gap-3 px-4 py-3 no-underline">
                  <span class="text-sm font-medium">{preset.custom ? protocolName(preset.protocol) : preset.name}</span>
                  <span class="hint text-xs">{preset.custom ? "" : protocolName(preset.protocol)}</span>
                </Link>
              {/each}
            </div>
          </Section>
        {/if}
      {/each}
    {:else if draft}
      <div class="grid gap-4">
        {@render setup()}
        {#if !mcp}{@render signIn()}{/if}
        {#if !saml}{@render clients()}{/if}

        <div class="flex gap-2 border-t border-[var(--line)] pt-5">
          <button type="button" class="btn btn-primary btn-sm" disabled={busy || !complete} onclick={save}>
            {busy ? t("providers.form.saving") : t("providers.form.add")}
          </button>
          <Link to="/providers" class="btn btn-ghost btn-sm">{t("providers.cancel")}</Link>
        </div>
      </div>
    {/if}
  </Page>
{:else if loading && !provider}
  <Spinner />
{:else if !provider}
  <div class="alert alert-error alert-soft text-sm" role="alert">{feedback.state.failure ?? t("providers.missing")}</div>
{:else}
  <Page title={provider.name} id={provider.key} back={{ to: "/providers", label: t("providers.back") }} {lede}>
    {#snippet after()}
      <Marks marks={providerMarks(provider)} />
    {/snippet}

    <Notices feedback={feedback.state} />

    {#if provider.archivedAt}
      <div class="callout callout-quiet" role="status">
        <div class="callout-words">
          <strong>{t("providers.callouts.archived", { day: day(provider.archivedAt) })}</strong>
        </div>
        <div class="callout-actions">
          <button type="button" class="btn btn-sm" onclick={restore}>{t("providers.restore")}</button>
        </div>
      </div>
    {:else if secretMissing(provider)}
      <div class="callout callout-warn" role="status">
        <div class="callout-words">
          <strong>{t("providers.callouts.no_secret")}</strong>
          <span>{t("providers.callouts.no_secret_detail", { name: provider.name })}</span>
        </div>
      </div>
    {/if}

    {#if provider.organization}
      <div class="callout callout-info">
        <div class="callout-words">
          <span>
            {t("providers.callouts.organization_lead")}
            <Link to={`/organizations/${provider.organization.key}`}>{provider.organization.name}</Link>.
            {t("providers.callouts.organization_rest")}
          </span>
        </div>
      </div>
    {/if}

    <Parts base={`/providers/${provider.key}`} {part} parts={PARTS} label={t("providers.parts.label")} />

    <div class="grid gap-4">
      {#if part === "sign-in" && !mcp}
        {@render signIn()}
      {:else if part === "clients" && !saml}
        {@render clients()}
      {:else if part === "accounts"}
        <Section>
          <Connections {api} {feedback} rows={connected} onchange={load} showActor />
        </Section>
      {:else}
        {@render setup()}

        {#if !provider.archivedAt}
          <Section row title={t("providers.danger")} lede={mcp ? t("providers.danger_lede_mcp") : t("providers.danger_lede")}>
            <div class="flex flex-wrap gap-2">
              {#if mcp}
                <button type="button" class="btn btn-sm" onclick={register}>{t("providers.register")}</button>
              {/if}
              <button type="button" class="btn btn-sm btn-error btn-outline" onclick={archive}>{t("providers.archive")}</button>
            </div>
          </Section>
        {/if}
      {/if}
    </div>

    {#if dirty}
      <div class="savebar" role="region" aria-label={t("providers.unsaved")}>
        <span class="text-sm font-medium">{t("providers.unsaved")}</span>
        <div class="flex gap-2">
          <button type="button" class="btn btn-ghost btn-sm" onclick={discard}>{t("providers.discard")}</button>
          <button type="button" class="btn btn-primary btn-sm" disabled={busy || !complete} onclick={save}>
            {busy ? t("providers.form.saving") : t("providers.form.save")}
          </button>
        </div>
      </div>
    {/if}
  </Page>
{/if}
