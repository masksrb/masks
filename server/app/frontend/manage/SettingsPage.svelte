<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import Events from "./Events.svelte";
  import Namespaces from "./Namespaces.svelte";
  import ScopesEditor from "./ScopesEditor.svelte";
  import BarChart from "./ui/BarChart.svelte";
  import Section from "./ui/Section.svelte";
  import Select from "./ui/Select.svelte";
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
        browsersOnly blockedAgents suspendAfter deleteAfter eventRetentionDays riskyNetworks
        signInPolicy { key name }
        signingKeys { kid algorithm activatedAt retiredAt state }
      }
      viewer { identifier scopes }
      tally { actors clients sessions devices }
      namespaces {
        name resource claimedAt releasable
        client { clientId name }
      }
      scopesSupported
      signInPolicies { key name }
    }
  `;

  const EVENT_FIELDS = `
    id action label createdAt ipAddress details
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

  const RETENTION = [
    [30, "30 days"],
    [90, "90 days"],
    [180, "180 days"],
    [365, "A year"],
    [1095, "Three years"],
    [2555, "Seven years"],
  ];

  const SUSPEND_AFTER = [
    [0, "Never"],
    [90, "After 90 days"],
    [180, "After 180 days"],
    [365, "After a year"],
    [730, "After two years"],
  ];

  const DELETE_AFTER = [
    [0, "Never"],
    [180, "After 180 days"],
    [365, "After a year"],
    [730, "After two years"],
    [1095, "After three years"],
  ];

  const choices = (listed, held) =>
    !held || listed.some(([days]) => days === held) ? listed : [...listed, [held, `After ${held} days`]];

  function deleteAfter(days) {
    if (days && !confirm("Delete idle accounts? A deleted account cannot be restored."))
      return load();

    return update({ deleteAfter: days }, "Idle accounts updated.");
  }

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
  let agents = $state("");
  let networks = $state("");
  let loading = $state(true);
  let days = $state(30);

  const counts = $derived(
    data
      ? [
          { to: "/actors", label: "Actors", value: data.tally.actors },
          { to: "/clients", label: "Clients", value: data.tally.clients },
          { to: "/actors", label: "Live sessions", value: data.tally.sessions },
          { to: "/actors#devices", label: "Devices", value: data.tally.devices },
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
      agents = data.tenant.blockedAgents ?? "";
      networks = data.tenant.riskyNetworks ?? "";
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
            $namedBy: String, $browsersOnly: Boolean, $blockedAgents: String, $signInPolicy: ID, $riskyNetworks: String,
            $suspendAfter: Int, $deleteAfter: Int, $eventRetentionDays: Int
          ) {
            updateTenant(
              name: $name
              dynamicClientScopes: $dynamicClientScopes
              dynamicRegistration: $dynamicRegistration
              namedBy: $namedBy
              browsersOnly: $browsersOnly
              blockedAgents: $blockedAgents
              riskyNetworks: $riskyNetworks
              signInPolicy: $signInPolicy
              suspendAfter: $suspendAfter
              deleteAfter: $deleteAfter
              eventRetentionDays: $eventRetentionDays
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

    <Section title="Sign-ins">
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
    </Section>

    <Loader load={() => api.query(RECENT)}>
      {#snippet children(recent)}
        {#if recent.worrying.length}
          <Section title="Worth a look">
            {#snippet actions()}
              <Link to="/activity" class="btn btn-sm">All activity</Link>
            {/snippet}

            <Events events={recent.worrying} />
          </Section>
        {/if}

        <Section title="Lately">
          {#snippet actions()}
            <Link to="/activity" class="btn btn-ghost btn-sm">All activity</Link>
          {/snippet}

          <Events events={recent.latest} empty="Nothing yet." />
        </Section>
      {/snippet}
    </Loader>
  </Page>
{:else}
  <Page title="General">
    <Notices feedback={feedback.state} />

    <div class="grid gap-4">
      <Section
        row
        title="Tenant"
        help="The name heads every screen and email masks sends. Apps discover this tenant at its issuer, and the manage API answers at its resource."
      >
        <Field label="Name" bind:value={name} onsave={() => update({ name }, "Renamed.")} />

        <Facts
          rows={[
            { term: "Subdomain", value: data.tenant.subdomain, mono: true },
            { term: "Issuer", value: boot.issuer, mono: true },
            { term: "Resource", value: boot.resource, mono: true },
            { term: "Serving since", value: day(data.tenant.createdAt) },
          ]}
        />
      </Section>

      <Section
        row
        title="Accounts are named by"
        help="What a person types to sign in. Every policy has to require whichever this names."
      >
        <Select
          value={data.tenant.namedBy}
          options={[["nickname", "Nickname"], ["email", "Email"], ["either", "Either"]]}
          onchange={(namedBy) => update({ namedBy }, "Naming updated.")}
        />
      </Section>

      <Section
        row
        title="Default policy"
        help="The sign-in policy for every client that has none of its own. Built-in offers passwords, passkeys, and providers, with an optional second factor."
      >
        <Select
          value={data.tenant.signInPolicy?.key ?? ""}
          options={[["", "Built-in"], ...data.signInPolicies.map((policy) => [policy.key, policy.name])]}
          onchange={(signInPolicy) => update({ signInPolicy }, "Default policy updated.")}
        />
      </Section>

      <Section
        row
        title="Who may sign in"
        help="Browsers only refuses any sign-in from something that does not present itself as a browser. Refused user agents takes fragments, separated by commas, and refuses every user agent that contains one."
      >
        <Switch
          label="Browsers only"
          checked={data.tenant.browsersOnly}
          onchange={(browsersOnly) =>
            update({ browsersOnly }, "Sign-in rules updated.")}
        />

        <Field
          label="Refused user agents"
          bind:value={agents}
          placeholder="curl, python-requests"
          onsave={() => update({ blockedAgents: agents }, "Sign-in rules updated.")}
        />

        <label class="flex flex-col gap-1.5">
          <span class="field-label">Risky networks</span>
          <textarea class="textarea w-full font-mono" rows="3" bind:value={networks} placeholder="203.0.113.0/24"></textarea>
          <span class="hint">
            Address ranges, one per line, that add to a sign-in's risk score. A sign-in policy decides what a score does.
          </span>
        </label>
        <div>
          <button type="button" class="btn btn-sm" onclick={() => update({ riskyNetworks: networks }, "Risky networks saved.")}>
            Save networks
          </button>
        </div>
      </Section>

      <Section
        row
        title="Idle accounts"
        help="An account nobody signs in to or uses through an app is suspended, then deleted, after these periods. Each step is warned by email at least 30 days ahead, and signing in before a suspension keeps the account. With Suspend set, only accounts suspended for being idle are deleted. With Suspend at Never, idle accounts are deleted directly. The last manager and accounts a provider provisions over SCIM are left alone."
      >
        <div class="grid gap-3 sm:grid-cols-2">
          <Select
            label="Suspend"
            value={data.tenant.suspendAfter ?? 0}
            options={choices(SUSPEND_AFTER, data.tenant.suspendAfter)}
            onchange={(days) => update({ suspendAfter: Number(days) }, "Idle accounts updated.")}
          />

          <Select
            label="Delete"
            value={data.tenant.deleteAfter ?? 0}
            options={choices(DELETE_AFTER, data.tenant.deleteAfter).map(([days, label]) => [
              days,
              label,
              days > 0 && days <= (data.tenant.suspendAfter ?? 0),
            ])}
            onchange={(days) => deleteAfter(Number(days))}
          />
        </div>
      </Section>

      <Section
        row
        title="Activity"
        help="How long masks keeps events. Older ones are deleted each night, and a shorter period takes effect at the next sweep. Export a range from Activity before shortening it."
      >
        <Select
          value={data.tenant.eventRetentionDays}
          options={choices(RETENTION, data.tenant.eventRetentionDays)}
          onchange={(days) => update({ eventRetentionDays: Number(days) }, "Activity is kept for the new period.")}
        />
      </Section>

      <Section
        row
        title="Dynamic registration"
        help="Whether apps may register themselves over RFC 7591. A self-registered app is never approved, and with the limit on it may ask only for the scopes chosen here."
      >
        <Select
          value={data.tenant.dynamicRegistration}
          options={[["off", "Off"], ["anything", "On"], ["bounded", "On, limited to these scopes"]]}
          onchange={(dynamicRegistration) =>
            update({ dynamicRegistration }, "Dynamic registration updated.")}
        />

        <ScopesEditor
          value={data.tenant.dynamicClientScopes ?? []}
          available={data.scopesSupported}
          onchange={(dynamicClientScopes) => update({ dynamicClientScopes }, "Ceiling updated.")}
        />
      </Section>

      {#if data.namespaces.length}
        <Namespaces {api} rows={data.namespaces} onreleased={load} showClient />
      {/if}

      <Section
        title="Signing keys"
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
                  <td class="hidden text-xs opacity-85 sm:table-cell">
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
      </Section>
    </div>
  </Page>
{/if}
