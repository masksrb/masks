<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import ScopesEditor from "./ScopesEditor.svelte";
  import BarChart from "./ui/BarChart.svelte";
  import Card from "./ui/Card.svelte";
  import Facts from "./ui/Facts.svelte";
  import Field from "./ui/Field.svelte";
  import Link from "./ui/Link.svelte";
  import Loader from "./ui/Loader.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api, boot, overview = false } = $props();

  const QUERY = `
    query Tenant {
      tenant {
        uuid subdomain name dynamicClientScopes createdAt
        signingKeys { kid algorithm activatedAt retiredAt state }
      }
      viewer { nickname scopes }
      tally { actors clients sessions devices }
      scopesSupported
    }
  `;

  const ACTIVITY = `
    query Activity($days: Int) {
      activity(days: $days) { date signIns }
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
  let loading = $state(true);
  let days = $state(30);

  const counts = $derived(
    data
      ? [
          { to: "/people", label: "People", value: data.tally.actors },
          { to: "/clients", label: "Clients", value: data.tally.clients },
          { to: "/people", label: "Live sessions", value: data.tally.sessions },
          { to: "/people", label: "Devices", value: data.tally.devices },
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
          `mutation Update($name: String, $dynamicClientScopes: [String!]) {
            updateTenant(name: $name, dynamicClientScopes: $dynamicClientScopes) { tenant { name } }
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
    lede="Everything this server holds for {data.tenant.name}, and who is using it right now."
  >
    <div class="tally">
      {#each counts as count (count.label)}
        <Link to={count.to} class="tally-cell">
          <span class="tally-figure">{count.value}</span>
          <span class="tally-label">{count.label}</span>
        </Link>
      {/each}
    </div>

    <Card
      title="Sign-ins"
      lede="Every session started on this tenant, counted on the day it was authenticated."
    >
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

    <Card title="You are signed in as {data.viewer.nickname}">
      <p class="deck-sm">
        This page holds a bearer token issued for
        <span class="font-mono text-xs">{boot.resource}</span>, carrying
        <span class="font-mono text-xs">{data.viewer.scopes.join(" ")}</span>. Revoking it ends
        administration without ending the sign-in.
      </p>
    </Card>
  </Page>
{:else}
  <Page title="Settings" lede="How this tenant identifies itself, and what it hands out.">
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
          title="Ceiling on open registration"
          lede="The most a client registering itself may ask for. Leave it empty and anything outside the masks: namespace is grantable."
        >
          <ScopesEditor
            value={data.tenant.dynamicClientScopes ?? []}
            available={data.scopesSupported}
            onchange={(dynamicClientScopes) => update({ dynamicClientScopes }, "Ceiling updated.")}
          />
        </Card>

        <Card
          title="Signing keys"
          lede="Tokens are signed with the active key. Stage one to publish it ahead of time and activate it when clients have seen it; rotate to do both at once."
        >
          {#snippet actions()}
            <button type="button" class="btn btn-sm" onclick={stage}>Stage</button>
            <button type="button" class="btn btn-sm btn-outline" onclick={rotate}>Rotate now</button>
          {/snippet}

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr><th>Key</th><th>Algorithm</th><th>State</th><th>Activated</th><th></th></tr>
              </thead>
              <tbody>
                {#each data.tenant.signingKeys as key (key.kid)}
                  <tr>
                    <td class="font-mono text-xs">{key.kid.slice(0, 8)}</td>
                    <td class="text-xs">{key.algorithm}</td>
                    <td><span class="badge badge-sm {BADGE[key.state]}">{key.state}</span></td>
                    <td class="text-xs opacity-70">
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
