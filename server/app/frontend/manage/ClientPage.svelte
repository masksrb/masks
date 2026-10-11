<script>
  import Parts from "./ui/Parts.svelte";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, joined } from "./lib/format.js";
  import { POLICY_FIELDS, policyDifferences } from "./lib/policies.js";
  import Consents from "./Consents.svelte";
  import Events from "./Events.svelte";
  import Namespaces from "./Namespaces.svelte";
  import Tokens from "./Tokens.svelte";
  import ScopesEditor from "./ScopesEditor.svelte";
  import Section from "./ui/Section.svelte";
  import ClientLogo from "./ui/ClientLogo.svelte";
  import Facts from "./ui/Facts.svelte";
  import Field from "./ui/Field.svelte";
  import Switch from "./ui/Switch.svelte";
  import Lines from "./ui/Lines.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import { t } from "./lib/copy.js";

  let { api, clientId, part = null } = $props();

  const QUERY = `
    query Client($clientId: ID!) {
      client(clientId: $clientId) {
        clientId name dynamic approvedAt archivedAt secretExpiresAt createdAt
        tokenEndpointAuthMethod applicationType clientUri logoUri tosUri policyUri logoUrl(size: 128)
        subjectType sectorIdentifierUri
        redirectUris postLogoutRedirectUris grantTypes responseTypes resources
        requiredScopes allowedScopes allowedGroups
        backchannelLogoutUri backchannelLogoutSessionRequired
        requirePushedAuthorizationRequests requireSignedRequestObject consentRequired jwks jwksUri
        authorizationDetailsTypes authorizationDetailsSchemas consentLifetime
        accessTokenLifetime refreshTokenLifetime
        protocol samlEntityId samlCertificate samlNameIdFormat samlRequestsSigned samlIdpInitiated samlAttributes samlSloUrl
        signInPolicy { ${POLICY_FIELDS} }
        events(limit: 25) {
          id action label createdAt ipAddress details
          actor { uuid identifier }
          by { uuid identifier }
          device { id label }
        }
        approvedBy { identifier }
        namespaces { name resource claimedAt releasable }
        consents(limit: 25) {
          id scopes audience updatedAt expiresAt authorizationDetails
          actor { uuid identifier }
        }
        tokens(limit: 25) {
          id kind scopes audience parentId createdAt expiresAt
          actor { uuid identifier }
          device { id label }
        }
      }
      scopesSupported
      groups { key name }
      samlMetadataUrl
      signInPolicies { key name }
      defaultSignInPolicy { ${POLICY_FIELDS} }
    }
  `;

  const feedback = createFeedback();

  let client = $state(null);
  let supported = $state([]);
  let groups = $state([]);
  let roles = $state("");
  let policies = $state([]);
  let fallbackPolicy = $state(null);
  let name = $state("");
  let logoutUri = $state("");
  let jwksUri = $state("");
  let jwks = $state("");
  let declared = $state("");
  let lasts = $state("");
  let accessMinutes = $state("");
  let refreshDays = $state("");
  let method = $state("");
  let sector = $state("");
  let metadataUrl = $state("");
  let certificate = $state("");
  let entityId = $state("");
  let sloUrl = $state("");
  let links = $state({});
  let attributes = $state("");
  let loading = $state(true);
  let secret = $state(null);

  const NAME_IDS = [
    ["urn:oasis:names:tc:SAML:2.0:nameid-format:persistent", t("client.name_ids.persistent")],
    ["urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress", t("client.name_ids.email")],
  ];

  const saml = $derived(client?.protocol === "saml");

  const facts = $derived(
    client
      ? [
          {
            term: t("client.facts.origin"),
            value: client.dynamic ? t("client.facts.self_registered") : t("client.facts.approved"),
          },
          { term: t("client.facts.approved_by"), value: client.approvedBy?.identifier },
          { term: t("client.facts.registered"), value: day(client.createdAt) },
          { term: t("client.facts.grants"), value: joined(client.grantTypes), mono: true },
          { term: t("client.facts.response_types"), value: joined(client.responseTypes), mono: true },
        ]
      : [],
  );

  const SUBJECTS = [
    ["public", t("client.subjects.public")],
    ["pairwise", t("client.subjects.pairwise")],
  ];

  const GRANTS = [
    ["refresh_token", t("client.grants.refresh_token")],
    ["urn:ietf:params:oauth:grant-type:device_code", t("client.grants.device_code")],
    ["urn:ietf:params:oauth:grant-type:token-exchange", t("client.grants.token_exchange")],
  ];

  const LINKS = [
    ["logoUri", "logo_uri", "https://app.example.com/logo.png"],
    ["clientUri", "client_uri", "https://app.example.com"],
    ["tosUri", "tos_uri", "https://app.example.com/terms"],
    ["policyUri", "policy_uri", "https://app.example.com/privacy"],
  ].map(([key, copy, placeholder]) => [key, t(`client.links.${copy}.label`), placeholder]);

  async function saveLinks() {
    const changes = Object.fromEntries(LINKS.map(([key]) => [key, links[key].trim() || null]));
    const logoChanged = changes.logoUri && changes.logoUri !== client.logoUri;

    await update(changes, t("client.notices.saved"));

    if (logoChanged) setTimeout(load, 3000);
  }

  function saveLifetimes() {
    return update(
      {
        accessTokenLifetime: accessMinutes ? Number(accessMinutes) * 60 : 0,
        refreshTokenLifetime: refreshDays ? Number(refreshDays) * 86400 : 0,
        consentLifetime: lasts ? Number(lasts) * 86400 : 0,
      },
      t("client.notices.saved"),
    );
  }

  const SAML_DEFAULTS = "email = email\nname = name\ngiven_name = given_name\nfamily_name = family_name\npreferred_username = preferred_username";

  const differences = $derived(
    client?.signInPolicy && fallbackPolicy ? policyDifferences(client.signInPolicy, fallbackPolicy) : [],
  );

  const keyed = $derived(Boolean(client?.jwks || client?.jwksUri));

  const mapped = (held) =>
    Object.entries(held ?? {})
      .map(([attribute, claim]) => `${attribute} = ${claim}`)
      .join("\n");

  async function load() {
    loading = true;

    try {
      const data = await api.query(QUERY, { clientId });

      client = data.client;
      supported = data.scopesSupported;
      groups = data.groups;
      roles = (data.client?.allowedGroups ?? []).filter((held) => held.includes(":")).join(", ");
      policies = data.signInPolicies;
      fallbackPolicy = data.defaultSignInPolicy;
      name = data.client?.name ?? "";
      logoutUri = data.client?.backchannelLogoutUri ?? "";
      jwksUri = data.client?.jwksUri ?? "";
      jwks = data.client?.jwks ? JSON.stringify(data.client.jwks, null, 2) : "";
      lasts = data.client?.consentLifetime ? String(Math.round(data.client.consentLifetime / 86400)) : "";
      accessMinutes = data.client?.accessTokenLifetime ? String(Math.round(data.client.accessTokenLifetime / 60)) : "";
      refreshDays = data.client?.refreshTokenLifetime ? String(Math.round(data.client.refreshTokenLifetime / 86400)) : "";
      declared = Object.keys(data.client?.authorizationDetailsSchemas ?? {}).length
        ? JSON.stringify(data.client.authorizationDetailsSchemas, null, 2)
        : "";
      method = data.client?.tokenEndpointAuthMethod ?? "";
      sector = data.client?.sectorIdentifierUri ?? "";
      metadataUrl = data.samlMetadataUrl;
      certificate = data.client?.samlCertificate ?? "";
      entityId = data.client?.samlEntityId ?? "";
      sloUrl = data.client?.samlSloUrl ?? "";
      links = Object.fromEntries(LINKS.map(([key]) => [key, data.client?.[key] ?? ""]));
      attributes = mapped(data.client?.samlAttributes);
    } catch (thrown) {
      feedback.blame(thrown);
    } finally {
      loading = false;
    }
  }

  load();

  async function act(document, variables, notice) {
    const data = await feedback.attempt(() => api.query(document, variables), notice);

    if (data) await load();

    return data;
  }

  const update = (changes, notice) =>
    act(
      `mutation Update(
        $clientId: ID!, $name: String, $requiredScopes: [String!], $allowedScopes: [String!],
        $backchannelLogoutUri: String, $redirectUris: [String!],
        $postLogoutRedirectUris: [String!], $resources: [String!],
        $requirePushedAuthorizationRequests: Boolean, $consentRequired: Boolean,
        $signInPolicy: ID, $grantTypes: [String!], $jwksUri: String,
        $tokenEndpointAuthMethod: String, $requireSignedRequestObject: Boolean,
        $samlCertificate: String, $samlRequestsSigned: Boolean, $samlIdpInitiated: Boolean,
        $samlNameIdFormat: String, $samlEntityId: String, $samlAttributes: JSON, $samlSloUrl: String, $jwks: JSON,
        $subjectType: String, $sectorIdentifierUri: String, $dpopBoundAccessTokens: Boolean,
        $backchannelLogoutSessionRequired: Boolean, $clientUri: String, $logoUri: String,
        $tosUri: String, $policyUri: String, $authorizationDetailsTypes: [String!],
        $authorizationDetailsSchemas: JSON, $consentLifetime: Int, $allowedGroups: [String!],
        $accessTokenLifetime: Int, $refreshTokenLifetime: Int
      ) {
        updateClient(
          clientId: $clientId, name: $name, requiredScopes: $requiredScopes,
          allowedScopes: $allowedScopes, backchannelLogoutUri: $backchannelLogoutUri,
          redirectUris: $redirectUris, postLogoutRedirectUris: $postLogoutRedirectUris,
          resources: $resources,
          requirePushedAuthorizationRequests: $requirePushedAuthorizationRequests,
          consentRequired: $consentRequired,
          signInPolicy: $signInPolicy,
          grantTypes: $grantTypes,
          jwksUri: $jwksUri,
          tokenEndpointAuthMethod: $tokenEndpointAuthMethod,
          requireSignedRequestObject: $requireSignedRequestObject,
          samlCertificate: $samlCertificate,
          samlRequestsSigned: $samlRequestsSigned,
          samlIdpInitiated: $samlIdpInitiated,
          samlNameIdFormat: $samlNameIdFormat,
          samlEntityId: $samlEntityId,
          samlAttributes: $samlAttributes,
          samlSloUrl: $samlSloUrl,
          jwks: $jwks,
          subjectType: $subjectType,
          sectorIdentifierUri: $sectorIdentifierUri,
          dpopBoundAccessTokens: $dpopBoundAccessTokens,
          backchannelLogoutSessionRequired: $backchannelLogoutSessionRequired,
          clientUri: $clientUri,
          logoUri: $logoUri,
          tosUri: $tosUri,
          policyUri: $policyUri,
          authorizationDetailsTypes: $authorizationDetailsTypes,
          authorizationDetailsSchemas: $authorizationDetailsSchemas,
          consentLifetime: $consentLifetime
          accessTokenLifetime: $accessTokenLifetime
          refreshTokenLifetime: $refreshTokenLifetime
          allowedGroups: $allowedGroups
        ) {
          client { clientId }
        }
      }`,
      { clientId, ...changes },
      notice,
    );

  const roleList = (value) =>
    value
      .split(/[\s,]+/)
      .map((held) => held.trim())
      .filter((held) => held.includes(":"));

  function admit(key, on) {
    const held = client.allowedGroups.filter((group) => group !== key);

    update({ allowedGroups: on ? [...held, key] : held }, t("client.notices.groups"));
  }

  function saveRoles() {
    const kept = client.allowedGroups.filter((group) => !group.includes(":"));

    update({ allowedGroups: [...kept, ...roleList(roles)] }, t("client.notices.groups"));
  }

  const unattended = $derived(client?.grantTypes.includes("client_credentials") ?? false);

  const granting = (grant, on) =>
    on ? [...new Set([...client.grantTypes, grant])] : client.grantTypes.filter((held) => held !== grant);

  function signsInAsItself(on) {
    update(
      { grantTypes: granting("client_credentials", on) },
      on
        ? t("client.notices.unattended_on")
        : t("client.notices.unattended_off"),
    );
  }

  function knowsActorsAs(chosen) {
    const question = t("client.confirm.subject");

    if (chosen === client.subjectType || !confirm(question)) {
      load();
      return;
    }

    update({ subjectType: chosen }, t("client.notices.subject"));
  }

  function saveKeys(held) {
    const pending = method === "private_key_jwt" && client.tokenEndpointAuthMethod !== "private_key_jwt";
    const changes = pending ? { ...held, tokenEndpointAuthMethod: method } : held;

    update(changes, pending ? t("client.notices.keys_signing") : t("client.notices.keys"));
  }

  function saveKeySet() {
    const text = jwks.trim();

    if (!text) {
      saveKeys({ jwks: null });
      return;
    }

    try {
      saveKeys({ jwks: JSON.parse(text), jwksUri: null });
    } catch {
      feedback.blame(new Error(t("client.errors.jwks")));
    }
  }

  function saveDeclared() {
    const text = declared.trim();

    try {
      update({ authorizationDetailsSchemas: text ? JSON.parse(text) : {} }, t("client.notices.declared"));
    } catch {
      feedback.blame(new Error(t("client.errors.declared")));
    }
  }

  function saveAttributes() {
    const pairs = attributes
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => line.split("=").map((part) => part.trim()));

    if (pairs.some((pair) => pair.length !== 2 || !pair[0] || !pair[1])) {
      feedback.blame(new Error(t("client.errors.attributes")));
      return;
    }

    update(
      { samlAttributes: Object.fromEntries(pairs) },
      pairs.length ? t("client.notices.attributes") : t("client.notices.attributes_default"),
    );
  }

  const METHODS = [
    ["client_secret_basic", t("client.methods.client_secret_basic")],
    ["client_secret_post", t("client.methods.client_secret_post")],
    ["private_key_jwt", t("client.methods.private_key_jwt")],
  ];

  function authenticates(chosen) {
    method = chosen;

    if (chosen === "private_key_jwt" && !keyed) return;

    const notice =
      chosen === "private_key_jwt"
        ? t("client.notices.signs_assertions")
        : client.tokenEndpointAuthMethod === "private_key_jwt"
          ? t("client.notices.uses_secret")
          : t("client.notices.saved");

    update({ tokenEndpointAuthMethod: chosen }, notice);
  }

  function restore() {
    if (!confirm(t("client.confirm.restore"))) return;

    act(
      `mutation Restore($clientId: ID!) {
        restoreClient(clientId: $clientId) { client { archivedAt } }
      }`,
      { clientId },
      t("client.notices.restored"),
    );
  }

  async function rotate() {
    if (!confirm(t("client.confirm.rotate"))) return;

    const data = await act(
      `mutation Rotate($clientId: ID!) { rotateClientSecret(clientId: $clientId) { secret } }`,
      { clientId },
      t("client.notices.rotated"),
    );

    if (data) secret = data.rotateClientSecret.secret;
  }

  function archive() {
    if (!confirm(t("client.confirm.archive"))) return;

    act(
      `mutation Archive($clientId: ID!) { archiveClient(clientId: $clientId) { client { archivedAt } } }`,
      { clientId },
      t("client.notices.archived"),
    );
  }
</script>

{#if loading && !client}
  <Spinner />
{:else if !client}
  <div class="alert alert-error alert-soft text-sm" role="alert">
    {feedback.state.failure ?? t("client.missing")}
  </div>
{:else}
  <Page title={client.name} id={client.clientId} back={{ to: "/clients", label: t("client.back") }}>
    <Notices feedback={feedback.state} />

    {#if client.archivedAt}
      <div class="alert alert-warning alert-soft flex-wrap items-center gap-3 text-sm" role="status">
        <span>{t("client.archived_on", { day: day(client.archivedAt) })}</span>
        <button type="button" class="btn btn-sm" onclick={restore}>{t("client.restore")}</button>
      </div>
    {/if}

    {#if secret}
      <div class="alert alert-warning alert-soft flex-col items-start gap-2" role="status">
        <span class="font-medium">{t("client.secret_once")}</span>
        <code class="font-mono text-sm break-all">{secret}</code>
      </div>
    {/if}

    <Parts
      base={`/clients/${clientId}`}
      {part}
      label={t("client.parts.label")}
      parts={[
        [null, "", t("client.parts.general")],
        ["access", "/access", t("client.parts.access")],
        ["endpoints", "/endpoints", t("client.parts.endpoints")],
        ["usage", "/usage", t("client.parts.usage")],
      ]}
    />

    <div class="grid gap-4">
      {#if part === "access"}
        <Section
          row
          title={t("client.groups.title")}
          lede={t("client.groups.lede")}
        >
          {#if groups.length}
            <div class="flex flex-col gap-1">
              {#each groups as group (group.key)}
                <label class="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-sm"
                    checked={client.allowedGroups.includes(group.key)}
                    onchange={(event) => admit(group.key, event.currentTarget.checked)}
                  />
                  {group.name} <code class="hint font-mono">{group.key}</code>
                </label>
              {/each}
            </div>
          {:else}
            <p class="text-sm opacity-85">
              {t("client.groups.none")} <Link to="/settings">{t("client.groups.add")}</Link> {t("client.groups.limit")}
            </p>
          {/if}

          <Field
            label={t("client.groups.roles")}
            bind:value={roles}
            placeholder="acme:owner, acme:billing"
            onsave={saveRoles}
          />

          <p class="hint">
            {client.allowedGroups.length
              ? t("client.groups.only", { groups: client.allowedGroups.join(", ") })
              : t("client.groups.everyone")}
          </p>
        </Section>

        <Section row title={t("client.scopes.title")}>
          <div class="flex flex-col gap-1.5">
            <span class="field-label">{t("client.scopes.always")}</span>
            <ScopesEditor
              value={client.requiredScopes}
              available={supported}
              onchange={(requiredScopes) => update({ requiredScopes }, t("client.notices.scopes"))}
            />
          </div>

          <div class="flex flex-col gap-1.5">
            <span class="field-label">{t("client.scopes.on_request")}</span>
            <ScopesEditor
              value={client.allowedScopes}
              available={supported}
              onchange={(allowedScopes) => update({ allowedScopes }, t("client.notices.scopes"))}
            />
          </div>
        </Section>
      {:else if part === "endpoints"}
        <Section row title={t("client.uris.title")}>
          <Lines
            label={saml ? t("client.uris.acs") : t("client.uris.redirect")}
            value={client.redirectUris}
            onsave={(redirectUris) => update({ redirectUris }, t("client.notices.redirects"))}
          />

          <Lines
            label={t("client.uris.post_logout")}
            value={client.postLogoutRedirectUris}
            onsave={(postLogoutRedirectUris) =>
              update({ postLogoutRedirectUris }, t("client.notices.post_logout"))}
          />

          <Lines
            label={t("client.uris.resources")}
            value={client.resources}
            onsave={(resources) => update({ resources }, t("client.notices.resources"))}
          />
        </Section>

        {#if !saml}
          <Section row title={t("client.keys.title")}>
            <p class="hint">
              {t("client.keys.hint")}
            </p>

            <Field
              label={t("client.keys.jwks_uri")}
              bind:value={jwksUri}
              placeholder="https://app.example.com/.well-known/jwks.json"
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              onsave={() => saveKeys(jwksUri.trim() ? { jwksUri: jwksUri.trim(), jwks: null } : { jwksUri: null })}
            />

            <label class="flex flex-col gap-1.5">
              <span class="field-label">{t("client.keys.jwks")}</span>
              <textarea
                class="textarea textarea-sm w-full font-mono text-xs"
                rows="4"
                spellcheck="false"
                placeholder={'{ "keys": [ ... ] }'}
                bind:value={jwks}
              ></textarea>
              <button type="button" class="btn btn-sm self-start" onclick={saveKeySet}>{t("client.save")}</button>
            </label>

            {#if keyed}
              <Switch
                checked={client.requireSignedRequestObject}
                label={t("client.keys.jar")}
                onchange={(on) =>
                  update(
                    { requireSignedRequestObject: on },
                    on
                      ? t("client.notices.jar_on")
                      : t("client.notices.jar_off"),
                  )}
              />
            {/if}
          </Section>
        {/if}

        {#if !saml}
          <Section row title={t("client.details.title")}>
            <p class="hint">
              {t("client.details.hint")}
            </p>

            <Lines
              label={t("client.details.types")}
              value={client.authorizationDetailsTypes}
              onsave={(authorizationDetailsTypes) => update({ authorizationDetailsTypes }, t("client.notices.types"))}
            />

            {#if client.approvedAt}
              <label class="flex flex-col gap-1.5">
                <span class="field-label">{t("client.details.accepts")}</span>
                <textarea
                  class="textarea textarea-sm w-full font-mono text-xs"
                  rows="6"
                  spellcheck="false"
                  placeholder={'{ "payment_initiation": { "label": "Send a payment", "schema": { "type": "object" } } }'}
                  bind:value={declared}
                ></textarea>
                <button type="button" class="btn btn-sm self-start" onclick={saveDeclared}>{t("client.save")}</button>
              </label>
            {/if}
          </Section>
        {/if}
      {:else if part === "usage"}
        <Section title={t("client.consents")}>
          <Consents {api} {feedback} rows={client.consents} onchange={load} showActor />
        </Section>

        <Section title={t("client.tokens")}>
          <Tokens {api} {feedback} rows={client.tokens} onchange={load} showActor />
        </Section>

        <Section title={t("client.activity.title")}>
          {#snippet actions()}
            <Link to={`/activity?client=${client.clientId}`} class="btn btn-ghost btn-sm">{t("client.activity.all")}</Link>
          {/snippet}

          <Events events={client.events} empty={t("client.activity.empty")} />
        </Section>

        {#if client.namespaces.length}
          <Namespaces {api} rows={client.namespaces} onreleased={load} />
        {/if}
      {:else}
        <Section row title={t("client.registration.title")}>
          <Field label={t("client.registration.name")} bind:value={name} onsave={() => update({ name }, t("client.notices.renamed"))} />

          <Facts rows={facts} />

          {#if saml}
            <p class="hint">{t("client.registration.saml")}</p>
          {:else if client.tokenEndpointAuthMethod === "none"}
            <p class="hint">{t("client.registration.public")}</p>
          {:else}
            <label class="flex flex-col gap-1.5">
              <span class="field-label">{t("client.registration.authenticates")}</span>
              <select
                class="select select-sm w-full"
                value={method}
                onchange={(event) => authenticates(event.currentTarget.value)}
              >
                {#each METHODS as [key, label] (key)}
                  <option value={key}>{label}</option>
                {/each}
              </select>
            </label>
          {/if}

          {#if method === "private_key_jwt" && !keyed}
            <p class="text-xs text-warning">{t("client.registration.needs_keys")}</p>
          {/if}

          {#if !saml}
            <label class="flex flex-col gap-1.5">
              <span class="field-label">{t("client.registration.knows_as")}</span>
              <select
                class="select select-sm w-full"
                value={client.subjectType}
                onchange={(event) => knowsActorsAs(event.currentTarget.value)}
              >
                {#each SUBJECTS as [key, label] (key)}
                  <option value={key}>{label}</option>
                {/each}
              </select>
            </label>

            {#if client.subjectType === "pairwise" || client.sectorIdentifierUri}
              <Field
                label={t("client.registration.sector")}
                bind:value={sector}
                placeholder={t("client.registration.sector_placeholder")}
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
                onsave={() =>
                  update(
                    { sectorIdentifierUri: sector.trim() || null },
                    sector.trim() ? t("client.notices.saved") : t("client.notices.cleared"),
                  )}
              />
            {/if}

            {#each GRANTS as [grant, label] (grant)}
              <Switch
                checked={client.grantTypes.includes(grant)}
                {label}
                onchange={(on) => update({ grantTypes: granting(grant, on) }, t("client.notices.grants"))}
              />
            {/each}
          {/if}

          {#if client.approvedAt && client.tokenEndpointAuthMethod !== "none"}
            <Switch
              checked={unattended}
              label={t("client.registration.unattended")}
              onchange={signsInAsItself}
            />
          {/if}

          <div class="flex flex-wrap gap-2 pt-1">
            {#if client.tokenEndpointAuthMethod.startsWith("client_secret")}
              <button type="button" class="btn btn-sm" onclick={rotate}>{t("client.registration.rotate")}</button>
            {/if}
            {#if !client.archivedAt}
              <button type="button" class="btn btn-sm btn-error btn-outline" onclick={archive}>
                {t("client.registration.archive")}
              </button>
            {/if}
          </div>
        </Section>

        {#if saml}
          <Section row title={t("client.saml.title")}>
            <Field
              label={t("client.saml.entity_id")}
              bind:value={entityId}
              autocapitalize="none"
              autocorrect="off"
              spellcheck="false"
              onsave={() => update({ samlEntityId: entityId.trim() }, t("client.notices.entity_id"))}
            />

            <div class="flex flex-col gap-1.5">
              <Field
                label={t("client.saml.slo_url")}
                bind:value={sloUrl}
                placeholder="https://wiki.example.com/saml/slo"
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
                onsave={() =>
                  update(
                    { samlSloUrl: sloUrl.trim() || null },
                    sloUrl.trim() ? t("client.notices.saved") : t("client.notices.cleared"),
                  )}
              />
              <span class="hint">{t("client.saml.slo_url_hint")}</span>
            </div>

            <Facts
              rows={[
                { term: t("client.saml.metadata"), value: metadataUrl, mono: true },
                { term: t("client.saml.initiate"), value: client.samlIdpInitiated ? `/saml/initiate/${client.clientId}` : null, mono: true },
              ]}
            />

            <label class="flex flex-col gap-1.5">
              <span class="field-label">{t("client.saml.names_by")}</span>
              <select
                class="select select-sm w-full"
                value={client.samlNameIdFormat ?? NAME_IDS[0][0]}
                onchange={(event) => update({ samlNameIdFormat: event.currentTarget.value }, t("client.notices.saved"))}
              >
                {#each NAME_IDS as [format, label] (format)}
                  <option value={format}>{label}</option>
                {/each}
              </select>
            </label>

            <label class="flex flex-col gap-1.5">
              <span class="field-label">{t("client.saml.certificate")}</span>
              <textarea
                class="textarea textarea-sm w-full font-mono text-xs"
                rows="3"
                spellcheck="false"
                bind:value={certificate}
              ></textarea>
              <button
                type="button"
                class="btn btn-sm self-start"
                onclick={() =>
                  update(
                    { samlCertificate: certificate.trim() },
                    certificate.trim() ? t("client.notices.certificate_saved") : t("client.notices.certificate_removed"),
                  )}
              >
                {t("client.save")}
              </button>
            </label>

            <label class="flex flex-col gap-1.5">
              <span class="field-label">{t("client.saml.attributes")}</span>
              <textarea
                class="textarea textarea-sm w-full font-mono text-xs"
                rows="5"
                spellcheck="false"
                placeholder={SAML_DEFAULTS}
                bind:value={attributes}
              ></textarea>
              <span class="hint">{t("client.saml.attributes_hint")}</span>
              <button type="button" class="btn btn-sm self-start" onclick={saveAttributes}>{t("client.save")}</button>
            </label>

            <Switch
              checked={client.samlRequestsSigned}
              label={t("client.saml.requests_signed")}
              onchange={(on) =>
                update(
                  { samlRequestsSigned: on },
                  on ? t("client.notices.signed_refused") : t("client.notices.signed_read"),
                )}
            />

            <Switch
              checked={client.samlIdpInitiated}
              label={t("client.saml.idp_initiated")}
              onchange={(on) =>
                update(
                  { samlIdpInitiated: on },
                  on
                    ? t("client.notices.idp_initiated_on")
                    : t("client.notices.idp_initiated_off"),
                )}
            />
          </Section>
        {/if}

        <Section row title={t("client.shown.title")}>
          <div class="flex items-center gap-3">
            <ClientLogo {client} class="size-14 rounded-lg border border-base-300 text-xl" />
            <p class="hint">
              {#if !client.approvedAt}
                {t("client.shown.unapproved")}
              {:else}
                {t("client.shown.approved")}
              {/if}
            </p>
          </div>

          <form
            class="flex flex-col gap-3"
            onsubmit={(event) => {
              event.preventDefault();
              saveLinks();
            }}
          >
            {#each LINKS as [key, label, placeholder] (key)}
              <Field {label} bind:value={links[key]} {placeholder} autocapitalize="none" autocorrect="off" spellcheck="false" />
            {/each}

            <button type="submit" class="btn btn-sm self-start">{t("client.save")}</button>
          </form>
        </Section>

        <Section row title={t("client.sign_in.title")}>
          <label class="flex flex-col gap-1.5">
            <span class="field-label">{t("client.sign_in.policy")}</span>
            <select
              class="select select-sm w-full"
              value={client.signInPolicy?.key ?? ""}
              onchange={(event) =>
                update({ signInPolicy: event.currentTarget.value }, t("client.notices.policy"))}
            >
              <option value="">
                {t("client.sign_in.default", { name: fallbackPolicy?.name ?? t("client.sign_in.built_in") })}
              </option>
              {#each policies as policy (policy.key)}
                <option value={policy.key}>{policy.name}</option>
              {/each}
            </select>
          </label>

          {#if client.signInPolicy?.archivedAt}
            <p class="text-xs text-warning">
              {t("client.sign_in.archived", { name: client.signInPolicy.name, fallback: fallbackPolicy?.name })}
            </p>
          {:else if client.signInPolicy}
            {#if differences.length}
              <div class="flex flex-col gap-1.5">
                <span class="field-label">{t("client.sign_in.differs", { name: fallbackPolicy?.name })}</span>
                <dl class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
                  {#each differences as { term, value, instead } (term)}
                    <dt class="opacity-80">{term}</dt>
                    <dd>{value} <span class="opacity-75 line-through">{instead}</span></dd>
                  {/each}
                </dl>
              </div>
            {:else}
              <p class="hint">{t("client.sign_in.same", { name: fallbackPolicy?.name })}</p>
            {/if}
          {/if}

          {#if !saml}
          <Switch
            checked={client.requirePushedAuthorizationRequests}
            label={t("client.sign_in.par")}
            onchange={(on) =>
              update(
                { requirePushedAuthorizationRequests: on },
                on ? t("client.notices.par_on") : t("client.notices.par_off"),
              )}
          />

          <Switch
            checked={client.dpopBoundAccessTokens}
            label={t("client.sign_in.dpop")}
            onchange={(on) =>
              update(
                { dpopBoundAccessTokens: on },
                on ? t("client.notices.dpop_on") : t("client.notices.dpop_off"),
              )}
          />
          {/if}

          {#if client.approvedAt}
            <Switch
              checked={client.consentRequired}
              label={t("client.sign_in.consent")}
              onchange={(on) =>
                update(
                  { consentRequired: on },
                  on
                    ? t("client.notices.consent_on")
                    : t("client.notices.consent_off"),
                )}
            />
          {/if}

          <form
            class="flex flex-col gap-3"
            onsubmit={(event) => {
              event.preventDefault();
              saveLifetimes();
            }}
          >
            <div class="grid gap-3 sm:grid-cols-3">
              <Field label={t("client.sign_in.access")} type="number" min="1" max="1440" bind:value={accessMinutes} />
              <Field label={t("client.sign_in.refresh")} type="number" min="1" max="400" bind:value={refreshDays} />
              <Field label={t("client.sign_in.consent_lifetime")} type="number" min="1" max="400" bind:value={lasts} />
            </div>

            <button type="submit" class="btn btn-sm self-start">{t("client.save")}</button>
          </form>

          <Field
            label={t("client.sign_in.logout")}
            bind:value={logoutUri}
            placeholder="https://app.example.com/logout"
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
            onsave={() =>
              update(
                { backchannelLogoutUri: logoutUri.trim() || null },
                logoutUri.trim() ? t("client.notices.saved") : t("client.notices.cleared"),
              )}
          />

          {#if client.backchannelLogoutUri}
            <Switch
              checked={client.backchannelLogoutSessionRequired}
              label={t("client.sign_in.logout_session")}
              onchange={(on) => update({ backchannelLogoutSessionRequired: on }, t("client.notices.saved"))}
            />
          {/if}
        </Section>
      {/if}
    </div>
  </Page>
{/if}
