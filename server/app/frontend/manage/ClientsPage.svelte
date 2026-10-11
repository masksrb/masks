<script>
  import { createPages } from "./lib/pages.svelte.js";
  import Pager from "./ui/Pager.svelte";
  import { NONE, day, joined } from "./lib/format.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import ScopesEditor from "./ScopesEditor.svelte";
  import Section from "./ui/Section.svelte";
  import ClientLogo from "./ui/ClientLogo.svelte";
  import Field from "./ui/Field.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Row from "./ui/Row.svelte";
  import Search from "./ui/Search.svelte";
  import Select from "./ui/Select.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Switch from "./ui/Switch.svelte";
  import Table from "./ui/Table.svelte";
  import { t } from "./lib/copy.js";

  let { api } = $props();

  const pages = createPages();

  const QUERY = `
    query Clients($search: String, $archived: Boolean, $afterId: ID, $limit: Int) {
      clients(search: $search, archived: $archived, afterId: $afterId, limit: $limit) {
        clientId name dynamic approvedAt archivedAt logoUrl(size: 64)
        requiredScopes allowedScopes resources createdAt
        approvedBy { identifier }
        namespaces { name }
      }
      clientCount(search: $search, archived: $archived)
    }
  `;

  const CREATE = `
    mutation Create(
      $name: String!, $grantTypes: [String!], $redirectUris: [String!],
      $resources: [String!], $allowedScopes: [String!]
    ) {
      createClient(
        name: $name, grantTypes: $grantTypes, redirectUris: $redirectUris,
        resources: $resources, allowedScopes: $allowedScopes
      ) {
        secret client { clientId name }
      }
    }
  `;

  const SAML = `
    mutation Saml($name: String!, $entityId: String!, $acsUrls: [String!]!, $certificate: String, $requestsSigned: Boolean) {
      createSamlApplication(
        name: $name, entityId: $entityId, acsUrls: $acsUrls, certificate: $certificate, requestsSigned: $requestsSigned
      ) {
        client { clientId name }
      }
    }
  `;

  const KINDS = [
    ["service", ["client_credentials"]],
    ["app", ["authorization_code", "refresh_token"]],
    ["saml", []],
    ["preset", []],
  ];

  const ADD_APP = `
    mutation AddApp($preset: ID!, $baseUrl: String!, $name: String, $slug: String) {
      addApp(preset: $preset, baseUrl: $baseUrl, name: $name, slug: $slug) {
        client { clientId name } secret guide settings { label value }
      }
    }
  `;

  const COLUMNS = [
    t("clients.columns.name"),
    { label: t("clients.columns.resources"), hide: true },
    t("clients.columns.source"),
    { label: t("clients.columns.namespaces"), hide: true, right: true },
    { label: t("clients.columns.scopes"), hide: true },
    { label: t("clients.columns.approved_by"), hide: true },
    { label: t("clients.columns.registered"), hide: true },
  ];

  const feedback = createFeedback();

  let adding = $state(false);
  let busy = $state(false);
  let created = $state(null);
  let supported = $state([]);
  let presets = $state([]);
  let draft = $state(blank());

  function blank() {
    return {
      name: "",
      kind: "service",
      redirects: "",
      resources: "",
      scopes: [],
      metadata: "",
      entityId: "",
      certificate: "",
      requestsSigned: false,
      preset: "",
      baseUrl: "",
      slug: "",
    };
  }

  const chosen = $derived(presets.find((preset) => preset.key === draft.preset));

  const lines = (text) =>
    text
      .split("\n")
      .map((one) => one.trim())
      .filter(Boolean);

  async function open() {
    draft = blank();
    created = null;
    adding = true;
    feedback.clear();

    if (supported.length) return;

    const data = await feedback.attempt(() =>
      api.query("query Scopes { scopesSupported appPresets { key name asks guide } }"),
    );

    if (!data) return;

    supported = data.scopesSupported;
    presets = data.appPresets;
  }

  async function readMetadata() {
    const data = await feedback.attempt(() =>
      api.query(
        `mutation Read($xml: String!) {
          readSamlApplicationMetadata(xml: $xml) { entityId acsUrls certificate requestsSigned }
        }`,
        { xml: draft.metadata },
      ),
    );

    if (!data) return;

    const read = data.readSamlApplicationMetadata;

    draft.entityId = read.entityId ?? draft.entityId;
    draft.redirects = read.acsUrls.join("\n") || draft.redirects;
    draft.certificate = read.certificate ?? draft.certificate;
    draft.requestsSigned = read.requestsSigned;
  }

  function request() {
    if (draft.kind === "preset") {
      return [
        ADD_APP,
        {
          preset: draft.preset,
          baseUrl: draft.baseUrl.trim(),
          name: draft.name.trim() || null,
          slug: draft.slug.trim() || null,
        },
        "addApp",
      ];
    }

    if (draft.kind === "saml") {
      return [
        SAML,
        {
          name: draft.name.trim(),
          entityId: draft.entityId.trim(),
          acsUrls: lines(draft.redirects),
          certificate: draft.certificate.trim() || null,
          requestsSigned: draft.requestsSigned,
        },
        "createSamlApplication",
      ];
    }

    return [
      CREATE,
      {
        name: draft.name.trim(),
        grantTypes: KINDS.find(([key]) => key === draft.kind)[1],
        redirectUris: draft.kind === "app" ? lines(draft.redirects) : [],
        resources: lines(draft.resources),
        allowedScopes: draft.scopes,
      },
      "createClient",
    ];
  }

  async function send() {
    const [document, variables, key] = request();

    busy = true;

    const data = await feedback.attempt(() => api.query(document, variables));

    busy = false;

    if (!data) return;

    created = data[key];
    adding = false;

    again();
  }

  let search = $state("");
  let query = $state("");
  let archived = $state(false);
  let clients = $state([]);
  let loading = $state(true);
  async function load() {
    loading = true;

    const data = await feedback.attempt(() =>
      api.query(QUERY, {
        search: query || null,
        archived,
        afterId: pages.cursor,
        limit: pages.size,
      }),
    );

    loading = false;

    if (!data) return;

    clients = data.clients;
    pages.counted(data.clientCount);
  }

  function turn(direction) {
    if (direction === "forward") pages.forward(clients.at(-1)?.clientId);
    else pages.back();

    load();
  }

  load();

  function again() {
    pages.reset();
    load();
  }

  function look() {
    query = search;
    again();
  }

  function toggle(held) {
    archived = held;
    again();
  }


  const nothing = $derived(
    query
      ? t(archived ? "clients.empty.archived_matches" : "clients.empty.matches", { query })
      : archived
        ? t("clients.empty.archived")
        : t("clients.empty.none"),
  );
</script>

<Page title={t("clients.title")}>
  {#snippet actions()}
    <Switch bind:checked={archived} label={t("clients.archived")} onchange={toggle} />
    <Search
      bind:value={search}
      label={t("clients.search")}
      placeholder={t("clients.search_placeholder")}
      onsearch={look}
    />
    <button type="button" class="btn btn-primary btn-sm" onclick={open}>{t("clients.add")}</button>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if adding}
    <Section title={t("clients.add")}>
      <Field label={t("clients.name")} bind:value={draft.name} placeholder={t("clients.name_placeholder")} />

      <div class="range" role="group" aria-label={t("clients.kind")}>
        {#each KINDS as [key] (key)}
          <button type="button" aria-pressed={draft.kind === key} onclick={() => (draft.kind = key)}>
            {t(`clients.kinds.${key}`)}
          </button>
        {/each}
      </div>

      {#if draft.kind === "preset"}
        <Select
          label={t("clients.app")}
          value={draft.preset}
          options={[["", t("clients.choose")], ...presets.map((preset) => [preset.key, preset.name])]}
          onchange={(key) => {
            draft.preset = key;
            draft.slug = presets.find((preset) => preset.key === key)?.asks?.name ?? "";
          }}
        />

        <Field label={t("clients.address")} bind:value={draft.baseUrl} placeholder="https://grafana.example.com" />

        {#if chosen?.asks?.name}
          <Field label={t("clients.slug")} bind:value={draft.slug} placeholder={chosen.asks.name} />
        {/if}
      {/if}

      <p class="hint">
        {draft.kind === "preset"
          ? t("clients.hints.preset")
          : draft.kind === "service"
          ? t("clients.hints.service")
          : draft.kind === "saml"
            ? t("clients.hints.saml")
            : t("clients.hints.app")}
      </p>

      {#if draft.kind === "saml"}
        <label class="flex flex-col gap-1.5">
          <span class="field-label">{t("clients.metadata")}</span>
          <textarea
            class="textarea textarea-sm w-full font-mono text-xs"
            rows="3"
            spellcheck="false"
            placeholder="<md:EntityDescriptor …"
            bind:value={draft.metadata}
          ></textarea>
        </label>
        <button
          type="button"
          class="btn btn-sm self-start"
          disabled={!draft.metadata.trim()}
          onclick={readMetadata}
        >
          {t("clients.read")}
        </button>

        <Field label={t("clients.entity_id")} bind:value={draft.entityId} placeholder="https://wiki.example.com/saml" />

        <label class="flex flex-col gap-1.5">
          <span class="field-label">{t("clients.acs")}</span>
          <textarea
            class="textarea textarea-sm w-full font-mono text-xs"
            rows="2"
            spellcheck="false"
            placeholder="https://wiki.example.com/saml/acs"
            bind:value={draft.redirects}
          ></textarea>
        </label>

        <label class="flex flex-col gap-1.5">
          <span class="field-label">{t("clients.certificate")}</span>
          <textarea
            class="textarea textarea-sm w-full font-mono text-xs"
            rows="2"
            spellcheck="false"
            bind:value={draft.certificate}
          ></textarea>
        </label>

        <Switch bind:checked={draft.requestsSigned} label={t("clients.requests_signed")} />
      {/if}

      {#if draft.kind === "app"}
        <label class="flex flex-col gap-1.5">
          <span class="field-label">{t("clients.redirect_uris")}</span>
          <textarea
            class="textarea textarea-sm w-full font-mono text-xs"
            rows="2"
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
            placeholder="https://app.example.com/callback"
            bind:value={draft.redirects}
          ></textarea>
        </label>
      {/if}

      {#if draft.kind !== "saml"}
      <label class="flex flex-col gap-1.5">
        <span class="field-label">{t("clients.resources")}</span>
        <textarea
          class="textarea textarea-sm w-full font-mono text-xs"
          rows="2"
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          placeholder="https://api.example.com/mcp"
          bind:value={draft.resources}
        ></textarea>
      </label>

      <div class="flex flex-col gap-2">
        <span class="legend">{t("clients.scopes")}</span>
        <ScopesEditor
          value={draft.scopes}
          available={supported}
          onchange={(chosen) => (draft.scopes = chosen)}
        />
      </div>
      {/if}

      <div class="flex gap-2">
        <button
          type="button"
          class="btn btn-primary btn-sm"
          disabled={busy ||
            (draft.kind === "preset"
              ? !draft.preset || !draft.baseUrl.trim()
              : !draft.name.trim() || (draft.kind === "saml" && !draft.entityId.trim()))}
          onclick={send}
        >
          {busy ? t("clients.adding") : t("clients.submit")}
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onclick={() => (adding = false)}>
          {t("clients.cancel")}
        </button>
      </div>
    </Section>
  {/if}

  {#if created}
    <Section title={t("clients.created.title", { name: created.client.name })}>
      <p class="text-sm opacity-85">
        {t(created.secret ? "clients.created.client_id_and_secret" : "clients.created.client_id")}
      </p>

      <p class="tray px-2 py-1 font-mono text-xs break-all">{created.client.clientId}</p>

      {#if created.secret}
        <p class="tray px-2 py-1 font-mono text-xs break-all">{created.secret}</p>
      {/if}

      {#if created.settings}
        <p class="text-sm opacity-85">
          {t("clients.created.settings", { name: created.client.name })}
          {#if created.guide}<a class="link" href={created.guide} target="_blank" rel="noreferrer">{t("clients.created.guide")}</a>.{/if}
        </p>

        <dl class="grid gap-x-4 gap-y-2 text-sm md:grid-cols-[auto_1fr]">
          {#each created.settings as setting (setting.label)}
            <dt class="font-mono text-xs opacity-80">{setting.label}</dt>
            <dd class="tray m-0 px-2 py-1 font-mono text-xs break-all whitespace-pre-wrap">{setting.value}</dd>
          {/each}
        </dl>
      {/if}

      <Link to={`/clients/${created.client.clientId}`} class="btn btn-sm self-start">{t("clients.created.open")}</Link>
    </Section>
  {/if}

  {#if loading && clients.length === 0}
    <Spinner />
  {:else}
    <Table columns={COLUMNS} count={clients.length} empty={nothing}>
      {#snippet rows()}
        {#each clients as client (client.clientId)}
          <Row to={`/clients/${client.clientId}`}>
            <td class="w-full max-w-0 md:w-auto md:max-w-[15rem]">
              <div class="flex items-center gap-2.5">
                <ClientLogo {client} class="size-8 rounded text-sm" />
                <div class="min-w-0">
                  <Link to={`/clients/${client.clientId}`} class="link link-hover font-medium">
                    {client.name}
                  </Link>
                  <div class="max-w-[11rem] truncate font-mono text-xs opacity-75" title={client.clientId}>
                    {client.clientId}
                  </div>
                </div>
              </div>
            </td>
            <td class="hidden md:table-cell">
              <div class="max-w-[11rem] truncate font-mono text-xs opacity-85" title={joined(client.resources)}>
                {joined(client.resources)}
              </div>
            </td>
            <td>
              {#if client.dynamic}
                <span class="badge badge-ghost badge-sm">{t("clients.self_registered")}</span>
              {:else}
                <span class="badge badge-success badge-sm">{t("clients.approved")}</span>
              {/if}
            </td>
            <td class="hidden text-right text-xs opacity-85 md:table-cell">
              {client.namespaces.length || NONE}
            </td>
            <td class="hidden font-mono text-xs md:table-cell">
              {#if client.requiredScopes.length}
                <div class="max-w-[12rem] truncate" title={joined(client.requiredScopes)}>
                  <span class="opacity-75">{t("clients.always")}</span>
                  {joined(client.requiredScopes)}
                </div>
              {/if}
              {#if client.allowedScopes.length}
                <div class="max-w-[12rem] truncate opacity-85" title={joined(client.allowedScopes)}>
                  <span class="opacity-85">{t("clients.on_request")}</span>
                  {joined(client.allowedScopes)}
                </div>
              {/if}
            </td>
            <td class="hidden text-xs opacity-85 md:table-cell">
              {client.approvedBy?.identifier ?? NONE}
            </td>
            <td class="hidden text-xs whitespace-nowrap opacity-85 md:table-cell">{day(client.createdAt)}</td>
          </Row>
        {/each}
      {/snippet}
    </Table>

    <Pager {pages} shown={clients.length} busy={loading} onpage={turn} />
  {/if}
</Page>
