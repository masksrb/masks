<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { t } from "./lib/copy.js";
  import { since } from "./lib/format.js";
  import Notices from "./ui/Notices.svelte";
  import Section from "./ui/Section.svelte";
  import Select from "./ui/Select.svelte";

  let { api } = $props();

  const QUERY = `
    query Domains {
      domainClaims { domain recordName recordValue verifiedAt missingSince provider { key name } }
      providers { key name }
      tenant { customHost origins }
    }
  `;

  const feedback = createFeedback();

  let data = $state(null);
  let busy = $state(false);
  let domain = $state("");
  let host = $state("");

  async function load() {
    const answer = await feedback.attempt(() => api.query(QUERY));

    if (answer) {
      data = answer;
      host = answer.tenant.customHost ?? "";
    }
  }

  load();

  const providerOptions = $derived([
    ["", t("domains.here")],
    ...(data?.providers ?? []).map((provider) => [provider.key, t("domains.to", { name: provider.name })]),
  ]);

  const proven = $derived((data?.domainClaims ?? []).filter((held) => held.verifiedAt));

  async function run(query, variables, notice) {
    busy = true;

    const answer = await feedback.attempt(() => api.query(query, variables), notice);

    busy = false;

    if (answer) await load();

    return answer;
  }

  async function claim() {
    const value = domain.trim();

    if (!value) return;

    const answer = await run(
      `mutation Claim($domain: String!) { claimDomain(domain: $domain) { domainClaim { domain } } }`,
      { domain: value },
      t("domains.claimed", { domain: value }),
    );

    if (answer) domain = "";
  }

  async function check(held) {
    busy = true;

    const answer = await feedback.attempt(() =>
      api.query(`mutation Check($domain: String!) { checkDomain(domain: $domain) { found } }`, { domain: held.domain }),
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

  function release(held) {
    if (!confirm(t("domains.release_confirm", { domain: held.domain }))) return;

    run(
      `mutation Release($domain: String!) { releaseDomain(domain: $domain) { domain } }`,
      { domain: held.domain },
      t("domains.released", { domain: held.domain }),
    );
  }

  function serve(value) {
    if (!value && !confirm(t("domains.stop_confirm", { host: data.tenant.customHost }))) return;

    run(
      `mutation Serve($host: String) { serveDomain(host: $host) { tenant { customHost } } }`,
      { host: value },
      value ? t("domains.served", { host: value }) : t("domains.unserved"),
    );
  }
</script>

<Section row title={t("domains.title")} help={t("domains.help")}>
  <Notices feedback={feedback.state} />

  {#if data}
    {#if data.domainClaims.length}
      <ul class="compact-list">
        {#each data.domainClaims as held (held.domain)}
          <li class="flex-wrap">
            <code class="min-w-0 truncate font-mono text-sm">{held.domain}</code>

            {#if held.missingSince}
              <span class="badge badge-warning badge-soft badge-sm">{t("domains.missing", { since: since(held.missingSince) })}</span>
            {:else if !held.verifiedAt}
              <span class="badge badge-ghost badge-sm">{t("domains.unproven")}</span>
            {/if}

            <div class="ml-auto flex items-center gap-1">
              {#if held.verifiedAt && !held.missingSince}
                <Select
                  name={t("domains.send", { domain: held.domain })}
                  value={held.provider?.key ?? ""}
                  options={providerOptions}
                  disabled={busy}
                  onchange={(key) => route(held, key)}
                />
              {:else}
                <button type="button" class="btn btn-sm" disabled={busy} onclick={() => check(held)}>{t("domains.check")}</button>
              {/if}
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                aria-label={t("domains.release", { domain: held.domain })}
                disabled={busy}
                onclick={() => release(held)}
              >×</button>
            </div>

            {#if !held.verifiedAt || held.missingSince}
              <p class="hint w-full">
                {t("domains.record")}
                <code class="font-mono text-xs break-all">{held.recordName}</code>
                <code class="font-mono text-xs break-all">{held.recordValue}</code>
              </p>
            {/if}
          </li>
        {/each}
      </ul>
    {/if}

    <form
      class="join"
      onsubmit={(event) => {
        event.preventDefault();
        claim();
      }}
    >
      <input
        class="input input-sm join-item w-full max-w-60 font-mono"
        aria-label={t("domains.new")}
        placeholder="acme.example"
        autocapitalize="none"
        spellcheck="false"
        bind:value={domain}
      />
      <button type="submit" class="btn btn-sm join-item" disabled={busy || !domain.trim()}>{t("domains.add")}</button>
    </form>

    {#if proven.length || data.tenant.customHost}
      <form
        class="flex flex-wrap items-center gap-2"
        onsubmit={(event) => {
          event.preventDefault();
          serve(host.trim());
        }}
      >
        <span class="text-sm">{t("domains.serve")}</span>
        <input
          class="input input-sm w-full max-w-60 font-mono"
          aria-label={t("domains.serve")}
          placeholder="login.{proven[0]?.domain ?? 'acme.example'}"
          autocapitalize="none"
          spellcheck="false"
          bind:value={host}
        />
        <button type="submit" class="btn btn-sm" disabled={busy || !host.trim() || host.trim() === data.tenant.customHost}>
          {t("domains.save")}
        </button>
        {#if data.tenant.customHost}
          <button type="button" class="btn btn-ghost btn-sm" disabled={busy} onclick={() => serve(null)}>{t("domains.stop")}</button>
        {/if}
      </form>
    {/if}
  {/if}
</Section>
