<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { t } from "./lib/copy.js";
  import { day } from "./lib/format.js";
  import { protocolName, providerMarks } from "./lib/providers.js";
  import { useRouter } from "./lib/router.svelte.js";
  import Link from "./ui/Link.svelte";
  import Marks from "./ui/Marks.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Row from "./ui/Row.svelte";
  import Section from "./ui/Section.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Table from "./ui/Table.svelte";

  let { api } = $props();

  const router = useRouter();

  const FIELDS = `
    key name protocol role trustsEmail receivesSignals delegates tokenAuthMethod secretHeld privateKeyHeld
    connections signedIn emailDomains archivedAt createdAt
    organization { key name }
  `;

  const QUERY = `
    query Providers {
      active: providers { ${FIELDS} }
      archived: providers(archived: true) { ${FIELDS} }
    }
  `;

  const COLUMNS = [
    t("providers.columns.provider"),
    { label: t("providers.columns.kind"), hide: true },
    { label: t("providers.columns.connections"), hide: true, right: true },
  ];

  const feedback = createFeedback();

  let active = $state([]);
  let archived = $state([]);
  let loading = $state(true);

  async function load() {
    const data = await feedback.attempt(() => api.query(QUERY));

    loading = false;

    if (!data) return;

    active = data.active;
    archived = data.archived;
  }

  load();

  async function restore(provider) {
    const done = await feedback.attempt(
      () =>
        api.query(`mutation Restore($key: ID!) { restoreProvider(key: $key) { provider { key } } }`, {
          key: provider.key,
        }),
      t("providers.notices.restored", { name: provider.name }),
    );

    if (done) await load();
  }
</script>

<Page title={t("providers.title")} lede={t("providers.lede")}>
  {#snippet actions()}
    <button type="button" class="btn btn-primary btn-sm" onclick={() => router.go("/providers/new")}>
      {t("providers.add")}
    </button>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if loading}
    <Spinner />
  {:else}
    <Table columns={COLUMNS} count={active.length} empty={t("providers.empty")}>
      {#snippet rows()}
        {#each active as provider (provider.key)}
          <Row to={`/providers/${provider.key}`}>
            <td class="w-full max-w-0 md:w-auto md:max-w-none">
              <div class="flex min-w-0 items-center gap-2">
                <Link to={`/providers/${provider.key}`} class="link link-hover truncate font-medium">{provider.name}</Link>
                <Marks marks={providerMarks(provider)} />
              </div>
              <div class="hint truncate text-xs">
                <span class="font-mono">{provider.key}</span>
                {#if provider.organization}· {provider.organization.name}{/if}
                <span class="md:hidden">· {protocolName(provider.protocol)}</span>
              </div>
            </td>
            <td class="hidden text-sm whitespace-nowrap md:table-cell">
              {protocolName(provider.protocol)}
              <div class="hint text-xs">
                {provider.protocol === "mcp"
                  ? t("providers.roles.never")
                  : provider.role === "delegate"
                    ? t("providers.roles.owns")
                    : t("providers.roles.existing")}
              </div>
            </td>
            <td class="hidden text-right text-sm whitespace-nowrap md:table-cell">
              {provider.connections}
              {#if provider.signedIn}
                <div class="hint text-xs">{t("providers.facts.signed_in", { count: provider.signedIn })}</div>
              {/if}
            </td>
          </Row>
        {/each}
      {/snippet}
    </Table>

    {#if archived.length}
      <Section title={t("providers.archived")}>
        <ul class="slats">
          {#each archived as provider (provider.key)}
            <li class="slat">
              <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                <span class="flex flex-wrap items-baseline gap-2">
                  <Link to={`/providers/${provider.key}`} class="link link-hover text-sm font-medium">{provider.name}</Link>
                  <span class="hint font-mono text-xs">{provider.key}</span>
                </span>
                <span class="flex items-baseline gap-3 text-xs">
                  <span class="hint">{t("providers.archived_on", { day: day(provider.archivedAt) })}</span>
                  <button type="button" class="link" onclick={() => restore(provider)}>{t("providers.restore")}</button>
                </span>
              </div>
            </li>
          {/each}
        </ul>
      </Section>
    {/if}
  {/if}
</Page>
