<script>
  import { t } from "./lib/copy.js";
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
    query Provisioning {
      scimBaseUrl
      provisioningTokens { id label usedAt expiresAt createdAt issuedBy { identifier } organization { name } }
      organizations { key name }
    }
  `;

  const LIFETIMES = [
    [30, "month"],
    [90, "quarter"],
    [365, "year"],
  ];

  const DAY = 86400;

  const feedback = createFeedback();

  let data = $state(null);
  let loading = $state(true);
  let label = $state("");
  let organization = $state("");
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
        `mutation Issue($label: String!, $expiresIn: Int, $organization: ID) {
          issueProvisioningToken(label: $label, expiresIn: $expiresIn, organization: $organization) { secret }
        }`,
        { label: label.trim() || "Provisioning", expiresIn: lifetime * DAY, organization: organization || null },
      ),
    );

    if (!done) return;

    issued = done.issueProvisioningToken;
    label = "";

    await load();
  }

  async function revoke(token) {
    if (!confirm(t("provisioning.revoke_confirm", { label: token.label }))) return;

    const done = await feedback.attempt(
      () =>
        api.query(
          `mutation Revoke($id: ID!) { revokeProvisioningToken(id: $id) { provisioningToken { id } } }`,
          { id: token.id },
        ),
      t("provisioning.revoked", { label: token.label }),
    );

    if (done) await load();
  }
</script>

<Page
  title={t("provisioning.title")}
  lede={t("provisioning.lede")}
>
  <Notices feedback={feedback.state} />

  {#if loading && !data}
    <Spinner />
  {:else if data}
    <div class="grid gap-4">
      <Section
        row
        title={t("provisioning.connect.title")}
        help={t("provisioning.connect.help")}
      >
        <div class="flex flex-col gap-1.5">
          <span class="field-label">{t("provisioning.connect.base_url")}</span>
          <code class="tray px-2 py-1 font-mono text-xs break-all">{data.scimBaseUrl}</code>
        </div>

        <Field label={t("provisioning.connect.label")} bind:value={label} placeholder="Entra ID" />

        {#if data.organizations.length}
          <Select
            label={t("provisioning.connect.provisions")}
            value={organization}
            options={[
              ["", t("provisioning.connect.every_account")],
              ...data.organizations.map((held) => [held.key, t("provisioning.connect.only_members", { name: held.name })]),
            ]}
            onchange={(key) => (organization = key)}
          />
        {/if}

        <div class="range" role="group" aria-label={t("provisioning.connect.lifetime")}>
          {#each LIFETIMES as [days, name] (days)}
            <button type="button" aria-pressed={lifetime === days} onclick={() => (lifetime = days)}>
              {t(`provisioning.lifetimes.${name}`)}
            </button>
          {/each}
        </div>

        <button type="button" class="btn btn-primary btn-sm self-start" onclick={issue}>{t("provisioning.connect.issue")}</button>

        {#if issued}
          <div class="alert alert-warning alert-soft flex-col items-start gap-2" role="status">
            <span class="font-medium">{t("provisioning.connect.shown_once")}</span>
            <code class="font-mono text-xs break-all">{issued.secret}</code>
          </div>
        {/if}
      </Section>

      <Section row title={t("provisioning.tokens.title")}>
        {#if data.provisioningTokens.length === 0}
          <p class="text-sm opacity-85">{t("provisioning.tokens.none")}</p>
        {:else}
          <ul class="flex flex-col divide-y divide-base-200">
            {#each data.provisioningTokens as token (token.id)}
              <li class="flex flex-wrap items-center justify-between gap-2 py-2">
                <div class="min-w-0">
                  <div class="text-sm font-medium">
                    {token.label}{#if token.organization}<span class="hint"> · {token.organization.name}</span>{/if}
                  </div>
                  <div class="text-xs opacity-80">
                    {token.issuedBy
                      ? t("provisioning.tokens.issued_by", {
                          identifier: token.issuedBy.identifier,
                          used: since(token.usedAt, t("provisioning.tokens.never")),
                          expires: day(token.expiresAt),
                        })
                      : t("provisioning.tokens.detail", {
                          used: since(token.usedAt, t("provisioning.tokens.never")),
                          expires: day(token.expiresAt),
                        })}
                  </div>
                </div>
                <button type="button" class="btn btn-ghost btn-sm" onclick={() => revoke(token)}>{t("provisioning.tokens.revoke")}</button>
              </li>
            {/each}
          </ul>
        {/if}
      </Section>
    </div>
  {/if}
</Page>
