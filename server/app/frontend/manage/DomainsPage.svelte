<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { t } from "./lib/copy.js";
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
      tenant { customHost origins }
    }
  `;

  const feedback = createFeedback();

  let data = $state(null);
  let loading = $state(true);
  let busy = $state(false);
  let draft = $state({ domain: "", provider: "" });
  let host = $state("");

  async function load() {
    loading = true;

    const answer = await feedback.attempt(() => api.query(QUERY));

    loading = false;

    if (answer) {
      data = answer;
      host = answer.tenant.customHost ?? "";
    }
  }

  load();

  const providerOptions = $derived([
    ["", t("domains.nowhere")],
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
      t("domains.claimed", { domain: draft.domain.trim() }),
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
      feedback.say(t("domains.proven", { domain: held.domain }));
    } else {
      feedback.blame(t("domains.unanswered", { name: held.recordName }));
    }

    await load();
  }

  function route(held, provider) {
    run(
      `mutation Route($domain: String!, $provider: ID) {
        updateDomainClaim(domain: $domain, provider: $provider) { domainClaim { domain } }
      }`,
      { domain: held.domain, provider: provider || null },
      provider ? t("domains.routed_away", { domain: held.domain }) : t("domains.routed_here", { domain: held.domain }),
    );
  }

  const proven = $derived((data?.domainClaims ?? []).filter((held) => held.verifiedAt));

  function serve(value) {
    run(
      `mutation Serve($host: String) { serveDomain(host: $host) { tenant { customHost } } }`,
      { host: value },
      value ? t("domains.served", { host: value }) : t("domains.unserved"),
    );
  }

  function stop() {
    if (!confirm(t("domains.stop_confirm", { host: data.tenant.customHost }))) return;

    serve(null);
  }

  function release(held) {
    if (!confirm(t("domains.release_confirm", { domain: held.domain }))) return;

    run(
      `mutation Release($domain: String!) { releaseDomain(domain: $domain) { domain } }`,
      { domain: held.domain },
      t("domains.released", { domain: held.domain }),
    );
  }
</script>

<Page title={t("domains.title")}>
  <Notices feedback={feedback.state} />

  {#if loading && !data}
    <Spinner />
  {:else if data}
    <Section
      title={t("domains.serve.title")}
      lede={t("domains.serve.lede")}
    >
      {#if proven.length === 0 && !data.tenant.customHost}
        <p class="hint">{t("domains.serve.prove_first")}</p>
      {:else}
        <div class="grid gap-3 sm:grid-cols-[1fr_auto_auto] sm:items-end">
          <Field label={t("domains.serve.host")} bind:value={host} placeholder="login.{proven[0]?.domain ?? 'acme.example'}" autocapitalize="none" spellcheck="false" />
          <button type="button" class="btn btn-primary btn-sm" disabled={busy || !host.trim() || host.trim() === data.tenant.customHost} onclick={() => serve(host.trim())}>{t("domains.serve.serve")}</button>
          {#if data.tenant.customHost}
            <button type="button" class="btn btn-ghost btn-sm" disabled={busy} onclick={stop}>{t("domains.serve.stop")}</button>
          {/if}
        </div>
        <p class="hint">
          {t("domains.serve.hint", { origins: data.tenant.origins.join(", ") })}
        </p>
      {/if}
    </Section>

    <Section
      title={t("domains.claim.title")}
      lede={t("domains.claim.lede")}
    >
      <div class="grid gap-3 sm:grid-cols-2">
        <Field label={t("domains.claim.domain")} bind:value={draft.domain} placeholder="acme.example" autocapitalize="none" spellcheck="false" />
        <Select label={t("domains.claim.send_to")} value={draft.provider} options={providerOptions} onchange={(key) => (draft.provider = key)} />
      </div>
      <div>
        <button type="button" class="btn btn-primary btn-sm" disabled={busy || !draft.domain.trim()} onclick={claim}>{t("domains.claim.claim")}</button>
      </div>
    </Section>

    {#each data.domainClaims as held (held.domain)}
      <Section title={held.domain}>
        {#snippet actions()}
          {#if held.verifiedAt}
            <span class="badge badge-success badge-sm">{t("domains.held.proven", { day: day(held.verifiedAt) })}</span>
          {:else}
            <span class="badge badge-ghost badge-sm">{t("domains.held.unproven")}</span>
          {/if}
        {/snippet}

        {#if !held.verifiedAt || held.missingSince}
          <div class="flex flex-col gap-1.5">
            <span class="field-label">{t("domains.held.record")}</span>
            <code class="tray px-2 py-1 font-mono text-xs break-all">{held.recordName}</code>
            <code class="tray px-2 py-1 font-mono text-xs break-all">{held.recordValue}</code>
          </div>
        {/if}

        {#if held.missingSince}
          <p class="text-sm text-warning">
            {t("domains.held.missing", { since: since(held.missingSince) })}
          </p>
        {/if}

        <div class="grid gap-3 sm:grid-cols-[1fr_auto_auto] sm:items-end">
          <Select
            label={t("domains.claim.send_to")}
            value={held.provider?.key ?? ""}
            options={providerOptions}
            disabled={busy}
            onchange={(key) => route(held, key)}
          />
          <button type="button" class="btn btn-sm" disabled={busy} onclick={() => check(held)}>{t("domains.held.check")}</button>
          <button type="button" class="btn btn-ghost btn-sm" disabled={busy} onclick={() => release(held)}>{t("domains.held.release")}</button>
        </div>

        <p class="hint">{t("domains.held.checked", { since: since(held.checkedAt, t("domains.held.never")) })}</p>
      </Section>
    {/each}
  {/if}
</Page>
