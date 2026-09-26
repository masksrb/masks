<script>
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
  import Spinner from "./ui/Spinner.svelte";
  import Switch from "./ui/Switch.svelte";
  import Table from "./ui/Table.svelte";

  let { api } = $props();

  const PAGE = 50;

  const QUERY = `
    query Clients($search: String, $archived: Boolean, $afterId: ID, $limit: Int) {
      clients(search: $search, archived: $archived, afterId: $afterId, limit: $limit) {
        clientId name dynamic approvedAt archivedAt logoUrl(size: 64)
        requiredScopes allowedScopes resources createdAt
        approvedBy { identifier }
        namespaces { name }
      }
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
    ["service", "Signs in as itself", ["client_credentials"]],
    ["app", "Signs actors in", ["authorization_code", "refresh_token"]],
    ["saml", "SAML app", []],
  ];

  const COLUMNS = [
    "Name",
    { label: "Resources", hide: true },
    "Source",
    { label: "Namespaces", hide: true, right: true },
    { label: "Scopes", hide: true },
    { label: "Approved by", hide: true },
    "Registered",
  ];

  const feedback = createFeedback();

  let adding = $state(false);
  let busy = $state(false);
  let created = $state(null);
  let supported = $state([]);
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
    };
  }

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

    const data = await feedback.attempt(() => api.query("query Scopes { scopesSupported }"));

    if (data) supported = data.scopesSupported;
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
        grantTypes: KINDS.find(([key]) => key === draft.kind)[2],
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
  let more = $state(false);
  let exhausted = $state(false);

  async function load(afterId = null) {
    if (afterId) more = true;
    else loading = true;

    const data = await feedback.attempt(() =>
      api.query(QUERY, {
        search: query || null,
        archived,
        afterId,
        limit: PAGE,
      }),
    );

    loading = false;
    more = false;

    if (!data) return;

    clients = afterId ? [...clients, ...data.clients] : data.clients;
    exhausted = data.clients.length < PAGE;
  }

  load();

  function again() {
    exhausted = false;
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

  const oldest = $derived(clients.at(-1)?.clientId ?? null);

  const nothing = $derived(
    query
      ? `No ${archived ? "archived " : ""}client matches “${query}”.`
      : archived
        ? "Nothing has been archived."
        : "No clients registered yet.",
  );
</script>

<Page title="Clients">
  {#snippet actions()}
    <Switch bind:checked={archived} label="Archived" onchange={toggle} />
    <Search
      bind:value={search}
      label="Search clients"
      placeholder="name or client_id"
      onsearch={look}
    />
    <button type="button" class="btn btn-primary btn-sm" onclick={open}>Add client</button>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if adding}
    <Section title="Add client">
      <Field label="Name" bind:value={draft.name} placeholder="Nightly indexer" />

      <div class="range" role="group" aria-label="What kind of client">
        {#each KINDS as [key, label] (key)}
          <button type="button" aria-pressed={draft.kind === key} onclick={() => (draft.kind = key)}>
            {label}
          </button>
        {/each}
      </div>

      <p class="text-xs opacity-60">
        {draft.kind === "service"
          ? "It asks the token endpoint for its own token with client_credentials. No actor is behind it, so it never holds openid, profile, email or masks:manage."
          : draft.kind === "saml"
            ? "It sends actors here with a SAML AuthnRequest, and masks posts a signed assertion back. Paste its metadata to fill the rest in."
            : "It sends actors to sign in and is handed a token on their behalf."}
      </p>

      {#if draft.kind === "saml"}
        <label class="flex flex-col gap-1.5">
          <span class="text-xs font-medium opacity-70">Its metadata</span>
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
          Read it
        </button>

        <Field label="Entity ID" bind:value={draft.entityId} placeholder="https://wiki.example.com/saml" />

        <label class="flex flex-col gap-1.5">
          <span class="text-xs font-medium opacity-70">Assertion consumer services</span>
          <textarea
            class="textarea textarea-sm w-full font-mono text-xs"
            rows="2"
            spellcheck="false"
            placeholder="https://wiki.example.com/saml/acs"
            bind:value={draft.redirects}
          ></textarea>
        </label>

        <label class="flex flex-col gap-1.5">
          <span class="text-xs font-medium opacity-70">Signing certificate, if it signs its requests</span>
          <textarea
            class="textarea textarea-sm w-full font-mono text-xs"
            rows="2"
            spellcheck="false"
            bind:value={draft.certificate}
          ></textarea>
        </label>

        <Switch bind:checked={draft.requestsSigned} label="Refuse requests it did not sign" />
      {/if}

      {#if draft.kind === "app"}
        <label class="flex flex-col gap-1.5">
          <span class="text-xs font-medium opacity-70">Redirect URIs</span>
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
        <span class="text-xs font-medium opacity-70">Resources</span>
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
        <span class="legend">Scopes</span>
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
          disabled={busy || !draft.name.trim() || (draft.kind === "saml" && !draft.entityId.trim())}
          onclick={send}
        >
          {busy ? "Adding..." : "Add the client"}
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onclick={() => (adding = false)}>
          Cancel
        </button>
      </div>
    </Section>
  {/if}

  {#if created}
    <Section title={`${created.client.name} is ready`}>
      <p class="text-sm opacity-70">
        Its client_id is below{created.secret ? ", with a secret shown this once. Copy it now" : ""}.
      </p>

      <p class="rounded bg-base-200 px-2 py-1 font-mono text-xs break-all">{created.client.clientId}</p>

      {#if created.secret}
        <p class="rounded bg-base-200 px-2 py-1 font-mono text-xs break-all">{created.secret}</p>
      {/if}

      <Link to={`/clients/${created.client.clientId}`} class="btn btn-sm self-start">Open it</Link>
    </Section>
  {/if}

  {#if loading && clients.length === 0}
    <Spinner />
  {:else}
    <Table columns={COLUMNS} count={clients.length} empty={nothing}>
      {#snippet rows()}
        {#each clients as client (client.clientId)}
          <Row to={`/clients/${client.clientId}`}>
            <td class="max-w-[15rem]">
              <div class="flex items-center gap-2.5">
                <ClientLogo {client} class="size-8 rounded text-sm" />
                <div class="min-w-0">
                  <Link to={`/clients/${client.clientId}`} class="link link-hover font-medium">
                    {client.name}
                  </Link>
                  <div class="truncate font-mono text-xs opacity-50" title={client.clientId}>
                    {client.clientId}
                  </div>
                </div>
              </div>
            </td>
            <td class="hidden max-w-[16rem] md:table-cell">
              <div class="truncate font-mono text-xs opacity-70" title={joined(client.resources)}>
                {joined(client.resources)}
              </div>
            </td>
            <td>
              {#if client.dynamic}
                <span class="badge badge-ghost badge-sm">self-registered</span>
              {:else}
                <span class="badge badge-success badge-sm">approved</span>
              {/if}
            </td>
            <td class="hidden text-right text-xs opacity-70 md:table-cell">
              {client.namespaces.length || NONE}
            </td>
            <td class="hidden max-w-64 font-mono text-xs md:table-cell">
              {#if client.requiredScopes.length}
                <div class="truncate" title={joined(client.requiredScopes)}>
                  <span class="opacity-50">always</span>
                  {joined(client.requiredScopes)}
                </div>
              {/if}
              {#if client.allowedScopes.length}
                <div class="truncate opacity-70" title={joined(client.allowedScopes)}>
                  <span class="opacity-70">on request</span>
                  {joined(client.allowedScopes)}
                </div>
              {/if}
            </td>
            <td class="hidden text-xs opacity-70 md:table-cell">
              {client.approvedBy?.identifier ?? NONE}
            </td>
            <td class="text-xs whitespace-nowrap opacity-70">{day(client.createdAt)}</td>
          </Row>
        {/each}
      {/snippet}
    </Table>

    {#if !exhausted && clients.length}
      <div>
        <button
          type="button"
          class="btn btn-ghost btn-sm"
          disabled={more}
          onclick={() => load(oldest)}
        >
          {more ? "Loading..." : "Show more"}
        </button>
      </div>
    {/if}
  {/if}
</Page>
