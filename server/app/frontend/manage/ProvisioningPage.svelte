<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, since } from "./lib/format.js";
  import Card from "./ui/Card.svelte";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api } = $props();

  const QUERY = `
    query Provisioning {
      scimBaseUrl
      provisioningTokens { id label usedAt expiresAt createdAt issuedBy { identifier } }
    }
  `;

  const LIFETIMES = [
    [30, "30 days"],
    [90, "90 days"],
    [365, "A year"],
  ];

  const DAY = 86400;

  const feedback = createFeedback();

  let data = $state(null);
  let loading = $state(true);
  let label = $state("");
  let lifetime = $state(90);
  let issued = $state(null);

  async function load() {
    loading = true;

    try {
      data = await api.query(QUERY);
    } catch (thrown) {
      feedback.blame(thrown);
    } finally {
      loading = false;
    }
  }

  load();

  async function issue() {
    const done = await feedback.attempt(() =>
      api.query(
        `mutation Issue($label: String!, $expiresIn: Int) {
          issueProvisioningToken(label: $label, expiresIn: $expiresIn) { secret }
        }`,
        { label: label.trim() || "Provisioning", expiresIn: lifetime * DAY },
      ),
    );

    if (!done) return;

    issued = done.issueProvisioningToken;
    label = "";

    await load();
  }

  async function revoke(token) {
    if (!confirm(`Revoke ${token.label}? Whatever provisions with it is refused from now on.`)) return;

    const done = await feedback.attempt(
      () =>
        api.query(
          `mutation Revoke($id: ID!) { revokeProvisioningToken(id: $id) { provisioningToken { id } } }`,
          { id: token.id },
        ),
      `${token.label} is revoked.`,
    );

    if (done) await load();
  }
</script>

<Page
  title="Provisioning"
  lede="An identity provider adds, changes, suspends and removes actors here over SCIM 2.0."
>
  <Notices feedback={feedback.state} />

  {#if loading && !data}
    <Spinner />
  {:else if data}
    <div class="grid gap-4">
      <Card title="Connect a provider">
        <div class="flex flex-col gap-1.5">
          <span class="text-xs font-medium opacity-70">SCIM base URL</span>
          <code class="rounded bg-base-200 px-2 py-1 font-mono text-xs break-all">{data.scimBaseUrl}</code>
        </div>

        <p class="text-xs opacity-60">
          Give it this URL and a token. A provisioned actor is known by their email, which masks takes as
          confirmed, and signs in through a provider or an invitation. Nobody who holds a masks: scope has
          their password or email changed this way, and the last manager is never suspended or removed.
        </p>

        <Field label="Label" bind:value={label} placeholder="Entra ID" />

        <div class="range" role="group" aria-label="How long the token lives">
          {#each LIFETIMES as [days, name] (days)}
            <button type="button" aria-pressed={lifetime === days} onclick={() => (lifetime = days)}>
              {name}
            </button>
          {/each}
        </div>

        <button type="button" class="btn btn-primary btn-sm self-start" onclick={issue}>Issue a token</button>

        {#if issued}
          <div class="alert alert-warning alert-soft flex-col items-start gap-2" role="status">
            <span class="font-medium">This token is shown once. Copy it now.</span>
            <code class="font-mono text-xs break-all">{issued.secret}</code>
          </div>
        {/if}
      </Card>

      <Card title="Tokens">
        {#if data.provisioningTokens.length === 0}
          <p class="text-sm opacity-70">None issued.</p>
        {:else}
          <ul class="flex flex-col divide-y divide-base-200">
            {#each data.provisioningTokens as token (token.id)}
              <li class="flex flex-wrap items-center justify-between gap-2 py-2">
                <div class="min-w-0">
                  <div class="text-sm font-medium">{token.label}</div>
                  <div class="text-xs opacity-60">
                    {token.issuedBy ? `by ${token.issuedBy.identifier}, ` : ""}used {since(token.usedAt, "never")},
                    expires {day(token.expiresAt)}
                  </div>
                </div>
                <button type="button" class="btn btn-ghost btn-sm" onclick={() => revoke(token)}>Revoke</button>
              </li>
            {/each}
          </ul>
        {/if}
      </Card>
    </div>
  {/if}
</Page>
