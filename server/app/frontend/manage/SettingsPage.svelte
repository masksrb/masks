<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import Events from "./Events.svelte";
  import Namespaces from "./Namespaces.svelte";
  import ScopesEditor from "./ScopesEditor.svelte";
  import BarChart from "./ui/BarChart.svelte";
  import Card from "./ui/Card.svelte";
  import Facts from "./ui/Facts.svelte";
  import Field from "./ui/Field.svelte";
  import Link from "./ui/Link.svelte";
  import Loader from "./ui/Loader.svelte";
  import Notices from "./ui/Notices.svelte";
  import Switch from "./ui/Switch.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api, boot, overview = false } = $props();

  const QUERY = `
    query Tenant {
      tenant {
        uuid subdomain name namedBy dynamicRegistration dynamicClientScopes createdAt
        mails mailFrom smtpAddress smtpPort smtpUsername smtpAuthentication smtpDomain smtpTls
        signingKeys { kid algorithm activatedAt retiredAt state }
      }
      viewer { identifier scopes }
      tally { actors clients sessions devices }
      namespaces {
        name resource claimedAt releasable
        client { clientId name }
      }
      scopesSupported
    }
  `;

  const EVENT_FIELDS = `
    id action createdAt ipAddress details
    actor { uuid identifier }
    by { uuid identifier }
    client { clientId name }
    device { id label }
  `;

  const ACTIVITY = `
    query Activity($days: Int) {
      activity(days: $days) { date signIns }
    }
  `;

  const RECENT = `
    query Recent {
      worrying: events(grave: true, limit: 8) { ${EVENT_FIELDS} }
      latest: events(limit: 8) { ${EVENT_FIELDS} }
    }
  `;

  const SPANS = [7, 30, 90];

  const BADGE = {
    staged: "badge-warning",
    active: "badge-success",
    retiring: "badge-info",
    retired: "badge-ghost",
  };

  const MARK = new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short" });

  const feedback = createFeedback();

  let data = $state(null);
  let name = $state("");
  let mail = $state(null);
  let secret = $state("");
  let loading = $state(true);
  let days = $state(30);

  const counts = $derived(
    data
      ? [
          { to: "/people", label: "People", value: data.tally.actors },
          { to: "/clients", label: "Clients", value: data.tally.clients },
          { to: "/people", label: "Live sessions", value: data.tally.sessions },
          { to: "/devices", label: "Devices", value: data.tally.devices },
        ]
      : [],
  );

  const plotted = (rows) =>
    rows.map((row) => ({
      key: row.date,
      value: row.signIns,
      label: MARK.format(new Date(`${row.date}T00:00:00`)),
    }));

  async function load() {
    loading = true;

    try {
      data = await api.query(QUERY);
      name = data.tenant.name;
      mail = {
        mailFrom: data.tenant.mailFrom ?? "",
        smtpAddress: data.tenant.smtpAddress ?? "",
        smtpPort: data.tenant.smtpPort ?? 587,
        smtpUsername: data.tenant.smtpUsername ?? "",
        smtpAuthentication: data.tenant.smtpAuthentication ?? "plain",
        smtpDomain: data.tenant.smtpDomain ?? "",
        smtpTls: data.tenant.smtpTls ?? false,
      };
      secret = "";
    } catch (thrown) {
      feedback.blame(thrown);
    } finally {
      loading = false;
    }
  }

  load();

  async function update(changes, notice) {
    const done = await feedback.attempt(
      () =>
        api.query(
          `mutation Update(
            $name: String, $dynamicClientScopes: [String!], $dynamicRegistration: String,
            $namedBy: String,
            $mailFrom: String, $smtpAddress: String, $smtpPort: Int, $smtpUsername: String,
            $smtpPassword: String, $smtpAuthentication: String, $smtpDomain: String,
            $smtpTls: Boolean
          ) {
            updateTenant(
              name: $name
              dynamicClientScopes: $dynamicClientScopes
              dynamicRegistration: $dynamicRegistration
              namedBy: $namedBy
              mailFrom: $mailFrom
              smtpAddress: $smtpAddress
              smtpPort: $smtpPort
              smtpUsername: $smtpUsername
              smtpPassword: $smtpPassword
              smtpAuthentication: $smtpAuthentication
              smtpDomain: $smtpDomain
              smtpTls: $smtpTls
            ) { tenant { name } }
          }`,
          changes,
        ),
      notice,
    );

    if (done) await load();
  }

  async function keys(query, variables, notice) {
    const done = await feedback.attempt(() => api.query(query, variables), notice);

    if (done) await load();
  }

  const stage = () =>
    keys(
      `mutation Stage { stageSigningKey { signingKey { kid } } }`,
      {},
      "Staged. Clients see it at the JWKS endpoint before it signs anything.",
    );

  function activate(kid) {
    if (!confirm("Sign every new token with this key? The current one keeps verifying for 24 hours."))
      return;

    return keys(
      `mutation Activate($kid: ID!) { activateSigningKey(kid: $kid) { signingKey { kid } } }`,
      { kid },
      "Activated.",
    );
  }

  function discard(kid) {
    if (!confirm("Discard this staged key? Nothing has been signed with it.")) return;

    return keys(
      `mutation Discard($kid: ID!) { discardSigningKey(kid: $kid) { kid } }`,
      { kid },
      "Discarded.",
    );
  }

  function rotate() {
    if (!confirm("Mint a key and sign with it immediately? The outgoing key keeps verifying for 24 hours."))
      return;

    return keys(
      `mutation Rotate { rotateSigningKey { signingKey { kid } } }`,
      {},
      "Rotated.",
    );
  }
</script>

{#if loading && !data}
  <Spinner />
{:else if !data}
  <div class="alert alert-error alert-soft text-sm" role="alert">{feedback.state.failure}</div>
{:else if overview}
  <Page
    title={data.tenant.name}
    id={boot.issuer}
    hero
  >
    <div class="tally">
      {#each counts as count (count.label)}
        <Link to={count.to} class="tally-cell">
          <span class="tally-figure">{count.value}</span>
          <span class="tally-label">{count.label}</span>
        </Link>
      {/each}
    </div>

    <Card title="Sign-ins">
      {#snippet actions()}
        <div class="range" role="group" aria-label="Time range">
          {#each SPANS as span (span)}
            <button type="button" aria-pressed={days === span} onclick={() => (days = span)}>
              {span}d
            </button>
          {/each}
        </div>
      {/snippet}

      {#key days}
        <Loader load={() => api.query(ACTIVITY, { days })}>
          {#snippet children(activity)}
            <BarChart points={plotted(activity.activity)} label="Sign-ins per day" />
          {/snippet}
        </Loader>
      {/key}
    </Card>

    <Loader load={() => api.query(RECENT)}>
      {#snippet children(recent)}
        {#if recent.worrying.length}
          <Card title="Worth a look" lede="Refusals, replays and blocks, newest first.">
            {#snippet actions()}
              <Link to="/activity" class="btn btn-sm">All activity</Link>
            {/snippet}

            <Events events={recent.worrying} />
          </Card>
        {/if}

        <Card title="Lately">
          {#snippet actions()}
            <Link to="/activity" class="btn btn-ghost btn-sm">All activity</Link>
          {/snippet}

          <Events events={recent.latest} empty="Nothing has happened yet." />
        </Card>
      {/snippet}
    </Loader>

    <Card title="You are signed in as {data.viewer.identifier}">
      <Facts
        rows={[
          { term: "Token for", value: boot.resource, mono: true },
          { term: "Carrying", value: data.viewer.scopes.join(" "), mono: true },
        ]}
      />
    </Card>
  </Page>
{:else}
  <Page title="Settings">
    <Notices feedback={feedback.state} />

    <div class="grid items-start gap-4 md:grid-cols-2">
      <Card title="Tenant">
        <Field label="Name" bind:value={name} onsave={() => update({ name }, "Renamed.")} />

        <Facts
          rows={[
            { term: "Subdomain", value: data.tenant.subdomain, mono: true },
            { term: "Issuer", value: boot.issuer, mono: true },
            { term: "Resource", value: boot.resource, mono: true },
            { term: "Serving since", value: day(data.tenant.createdAt) },
          ]}
        />
      </Card>

      <div class="flex flex-col gap-4">
        <Card
          title="What names an account"
          lede="Managers always need both a nickname and an address, whichever this is."
        >
          <select
            class="select select-sm w-full"
            value={data.tenant.namedBy}
            onchange={(event) =>
              update({ namedBy: event.currentTarget.value }, "Naming updated.")}
          >
            <option value="nickname">A nickname</option>
            <option value="email">An email address</option>
            <option value="either">Either one</option>
          </select>
        </Card>

        <Card
          title="Mail"
          lede={data.tenant.mails
            ? "Invitations, resets and confirmations are emailed from here."
            : "Nothing is emailed until a from address and a server are set. Until then, invitations and resets are links a manager passes along."}
        >
          {#if mail}
            <div class="grid gap-3 sm:grid-cols-2">
              <Field label="From address" type="email" bind:value={mail.mailFrom} />
              <Field label="Server" bind:value={mail.smtpAddress} placeholder="smtp.example.com" />
              <Field label="Port" type="number" bind:value={mail.smtpPort} />
              <Field label="Username" bind:value={mail.smtpUsername} />
              <Field
                label="Password"
                type="password"
                bind:value={secret}
                placeholder="unchanged"
              />
              <Field label="HELO domain" bind:value={mail.smtpDomain} />
            </div>

            <label class="flex flex-col gap-1.5">
              <span class="text-xs font-medium opacity-70">Authentication</span>
              <select class="select select-sm w-full" bind:value={mail.smtpAuthentication}>
                <option value="plain">plain</option>
                <option value="login">login</option>
                <option value="cram_md5">cram_md5</option>
              </select>
            </label>

            <Switch label="Implicit TLS — off means STARTTLS" bind:checked={mail.smtpTls} />

            <div class="flex gap-2">
              <button
                type="button"
                class="btn btn-primary btn-sm"
                onclick={() =>
                  update(
                    {
                      ...mail,
                      smtpPort: Number(mail.smtpPort) || 587,
                      ...(secret ? { smtpPassword: secret } : {}),
                    },
                    "Mail updated.",
                  )}
              >
                Save mail settings
              </button>
            </div>
          {/if}
        </Card>

        <Card
          title="Dynamic registration"
          lede="Whether an app may register itself here, and the most it may ask for."
        >
          <select
            class="select select-sm w-full"
            value={data.tenant.dynamicRegistration}
            onchange={(event) =>
              update(
                { dynamicRegistration: event.currentTarget.value },
                "Dynamic registration updated.",
              )}
          >
            <option value="off">Off — a manager adds every app by hand</option>
            <option value="anything">
              On, for anything a manager does not have to grant
            </option>
            <option value="bounded">On, held to the scopes below</option>
          </select>

          <ScopesEditor
            value={data.tenant.dynamicClientScopes ?? []}
            available={data.scopesSupported}
            onchange={(dynamicClientScopes) => update({ dynamicClientScopes }, "Ceiling updated.")}
          />
        </Card>

        {#if data.namespaces.length}
          <Namespaces {api} rows={data.namespaces} onreleased={load} showClient />
        {/if}

        <Card
          title="Signing keys"
          lede="Stage to publish ahead of time; rotate to do both at once."
        >
          {#snippet actions()}
            <button type="button" class="btn btn-sm" onclick={stage}>Stage</button>
            <button type="button" class="btn btn-sm btn-outline" onclick={rotate}>Rotate now</button>
          {/snippet}

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Key</th>
                  <th class="hidden sm:table-cell">Algorithm</th>
                  <th>State</th>
                  <th class="hidden sm:table-cell">Activated</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {#each data.tenant.signingKeys as key (key.kid)}
                  <tr>
                    <td class="font-mono text-xs">{key.kid.slice(0, 8)}</td>
                    <td class="hidden text-xs sm:table-cell">{key.algorithm}</td>
                    <td><span class="badge badge-sm {BADGE[key.state]}">{key.state}</span></td>
                    <td class="hidden text-xs opacity-70 sm:table-cell">
                      {#if key.state === "retiring"}
                        until {day(key.retiredAt)}
                      {:else}
                        {day(key.activatedAt, "not yet")}
                      {/if}
                    </td>
                    <td class="text-right whitespace-nowrap">
                      {#if key.state === "staged"}
                        <button type="button" class="btn btn-xs" onclick={() => activate(key.kid)}>
                          Activate
                        </button>
                        <button
                          type="button"
                          class="btn btn-xs btn-ghost"
                          onclick={() => discard(key.kid)}
                        >
                          Discard
                        </button>
                      {/if}
                    </td>
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        </Card>
      </div>
    </div>
  </Page>
{/if}
