<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, since } from "./lib/format.js";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Select from "./ui/Select.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api } = $props();

  const QUERY = `
    query Domains {
      domainClaims { domain recordName recordValue verifiedAt checkedAt missingSince provider { key name } }
      providers { key name }
    }
  `;

  const feedback = createFeedback();

  let data = $state(null);
  let loading = $state(true);
  let busy = $state(false);
  let draft = $state({ domain: "", provider: "" });

  async function load() {
    loading = true;

    const answer = await feedback.attempt(() => api.query(QUERY));

    loading = false;

    if (answer) data = answer;
  }

  load();

  const providerOptions = $derived([
    ["", "Nowhere yet"],
    ...(data?.providers ?? []).map((provider) => [provider.key, provider.name]),
  ]);

  async function run(query, variables, notice) {
    busy = true;

    const answer = await feedback.attempt(() => api.query(query, variables), notice);

    busy = false;

    if (answer) await load();

    return answer;
  }

  async function claim() {
    const answer = await run(
      `mutation Claim($domain: String!, $provider: ID) {
        claimDomain(domain: $domain, provider: $provider) { domainClaim { domain } }
      }`,
      { domain: draft.domain.trim(), provider: draft.provider || null },
      `Publish the TXT record below, then check ${draft.domain.trim()}.`,
    );

    if (answer) draft = { domain: "", provider: "" };
  }

  async function check(held) {
    busy = true;

    const answer = await feedback.attempt(() =>
      api.query(
        `mutation Check($domain: String!) { checkDomain(domain: $domain) { found } }`,
        { domain: held.domain },
      ),
    );

    busy = false;

    if (!answer) return;

    if (answer.checkDomain.found) {
      feedback.say(`${held.domain} is proven.`);
    } else {
      feedback.blame(`No matching TXT record at ${held.recordName} yet. DNS can take a while to spread.`);
    }

    await load();
  }

  function route(held, provider) {
    run(
      `mutation Route($domain: String!, $provider: ID) {
        updateDomainClaim(domain: $domain, provider: $provider) { domainClaim { domain } }
      }`,
      { domain: held.domain, provider: provider || null },
      provider ? `People at ${held.domain} go to their provider now.` : `People at ${held.domain} sign in here now.`,
    );
  }

  function release(held) {
    if (!confirm(`Release ${held.domain}? People with an address there sign in the usual way again.`)) return;

    run(
      `mutation Release($domain: String!) { releaseDomain(domain: $domain) { domain } }`,
      { domain: held.domain },
      `${held.domain} is released.`,
    );
  }
</script>

<Page title="Domains">
  <Notices feedback={feedback.state} />

  {#if loading && !data}
    <Spinner />
  {:else if data}
    <Section
      title="Claim a domain"
      lede="Someone who types an address at a proven domain goes straight to its provider, without a password. Prove the domain with a DNS record first."
    >
      <div class="grid gap-3 sm:grid-cols-2">
        <Field label="Domain" bind:value={draft.domain} placeholder="acme.example" autocapitalize="none" spellcheck="false" />
        <Select label="Send people to" value={draft.provider} options={providerOptions} onchange={(key) => (draft.provider = key)} />
      </div>
      <div>
        <button type="button" class="btn btn-primary btn-sm" disabled={busy || !draft.domain.trim()} onclick={claim}>Claim</button>
      </div>
    </Section>

    {#each data.domainClaims as held (held.domain)}
      <Section title={held.domain}>
        {#snippet actions()}
          {#if held.verifiedAt}
            <span class="badge badge-success badge-sm">Proven {day(held.verifiedAt)}</span>
          {:else}
            <span class="badge badge-ghost badge-sm">Not proven</span>
          {/if}
        {/snippet}

        {#if !held.verifiedAt || held.missingSince}
          <div class="flex flex-col gap-1.5">
            <span class="field-label">TXT record</span>
            <code class="rounded bg-base-200 px-2 py-1 font-mono text-xs break-all">{held.recordName}</code>
            <code class="rounded bg-base-200 px-2 py-1 font-mono text-xs break-all">{held.recordValue}</code>
          </div>
        {/if}

        {#if held.missingSince}
          <p class="text-sm text-warning">
            The record stopped answering {since(held.missingSince)}. The claim is released a week after that.
          </p>
        {/if}

        <div class="grid gap-3 sm:grid-cols-[1fr_auto_auto] sm:items-end">
          <Select
            label="Send people to"
            value={held.provider?.key ?? ""}
            options={providerOptions}
            disabled={busy}
            onchange={(key) => route(held, key)}
          />
          <button type="button" class="btn btn-sm" disabled={busy} onclick={() => check(held)}>Check now</button>
          <button type="button" class="btn btn-ghost btn-sm" disabled={busy} onclick={() => release(held)}>Release</button>
        </div>

        <p class="hint">Checked {since(held.checkedAt, "never")}. masks checks every hour.</p>
      </Section>
    {/each}
  {/if}
</Page>
