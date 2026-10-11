<script>
  import { t } from "./lib/copy.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";
  import Section from "./ui/Section.svelte";
  import Select from "./ui/Select.svelte";
  import Switch from "./ui/Switch.svelte";

  let { api } = $props();

  const QUERY = `
    query SignInRules {
      tenant { namedBy browsersOnly blockedAgents riskyNetworks suspendAfter deleteAfter signInPolicy { key } }
      signInPolicies { key name }
    }
  `;

  const SUSPEND_AFTER = [
    [0, t("settings.idle.never")],
    [90, t("settings.idle.after_90_days")],
    [180, t("settings.idle.after_180_days")],
    [365, t("settings.idle.after_a_year")],
    [730, t("settings.idle.after_two_years")],
  ];

  const DELETE_AFTER = [
    [0, t("settings.idle.never")],
    [180, t("settings.idle.after_180_days")],
    [365, t("settings.idle.after_a_year")],
    [730, t("settings.idle.after_two_years")],
    [1095, t("settings.idle.after_three_years")],
  ];

  const choices = (listed, held) =>
    !held || listed.some(([days]) => days === held) ? listed : [...listed, [held, t("settings.after_days", { days: held })]];

  const feedback = createFeedback();

  let data = $state(null);
  let agents = $state("");
  let networks = $state("");

  async function load() {
    const answer = await feedback.attempt(() => api.query(QUERY));

    if (!answer) return;

    data = answer;
    agents = answer.tenant.blockedAgents ?? "";
    networks = answer.tenant.riskyNetworks ?? "";
  }

  load();

  async function update(changes, notice) {
    const done = await feedback.attempt(
      () =>
        api.query(
          `mutation Update(
            $namedBy: String, $browsersOnly: Boolean, $blockedAgents: String, $signInPolicy: ID,
            $riskyNetworks: String, $suspendAfter: Int, $deleteAfter: Int
          ) {
            updateTenant(
              namedBy: $namedBy
              browsersOnly: $browsersOnly
              blockedAgents: $blockedAgents
              riskyNetworks: $riskyNetworks
              signInPolicy: $signInPolicy
              suspendAfter: $suspendAfter
              deleteAfter: $deleteAfter
            ) { tenant { name } }
          }`,
          changes,
        ),
      notice,
    );

    if (done) await load();
  }

  function deleteAfter(days) {
    if (days && !confirm(t("settings.idle.delete_confirm"))) return load();

    return update({ deleteAfter: days }, t("settings.idle.updated"));
  }
</script>

<Notices feedback={feedback.state} />

{#if data}
      <Section
        row
        title={t("settings.naming.title")}
        help={t("settings.naming.help")}
      >
        <Select
          value={data.tenant.namedBy}
          options={[
            ["nickname", t("settings.naming.nickname")],
            ["email", t("settings.naming.email")],
            ["either", t("settings.naming.either")],
          ]}
          onchange={(namedBy) => update({ namedBy }, t("settings.naming.updated"))}
        />
      </Section>

      <Section
        row
        title={t("settings.policy.title")}
        help={t("settings.policy.help")}
      >
        <Select
          value={data.tenant.signInPolicy?.key ?? ""}
          options={[["", t("settings.policy.built_in")], ...data.signInPolicies.map((policy) => [policy.key, policy.name])]}
          onchange={(signInPolicy) => update({ signInPolicy }, t("settings.policy.updated"))}
        />
      </Section>

      <Section
        row
        title={t("settings.access.title")}
        help={t("settings.access.help")}
      >
        <Switch
          label={t("settings.access.browsers_only")}
          checked={data.tenant.browsersOnly}
          onchange={(browsersOnly) =>
            update({ browsersOnly }, t("settings.access.updated"))}
        />

        <Field
          label={t("settings.access.refused_agents")}
          bind:value={agents}
          placeholder="curl, python-requests"
          onsave={() => update({ blockedAgents: agents }, t("settings.access.updated"))}
        />

        <label class="flex flex-col gap-1.5">
          <span class="field-label">{t("settings.access.risky_networks")}</span>
          <textarea class="textarea w-full font-mono" rows="3" bind:value={networks} placeholder="203.0.113.0/24"></textarea>
          <span class="hint">
            {t("settings.access.risky_hint")}
          </span>
        </label>
        <div>
          <button type="button" class="btn btn-sm" onclick={() => update({ riskyNetworks: networks }, t("settings.access.networks_saved"))}>
            {t("settings.access.save_networks")}
          </button>
        </div>
      </Section>

      <Section
        row
        title={t("settings.idle.title")}
        help={t("settings.idle.help")}
      >
        <div class="grid max-w-xl gap-3 sm:grid-cols-2">
          <Select
            label={t("settings.idle.suspend")}
            value={data.tenant.suspendAfter ?? 0}
            options={choices(SUSPEND_AFTER, data.tenant.suspendAfter)}
            onchange={(days) => update({ suspendAfter: Number(days) }, t("settings.idle.updated"))}
          />

          <Select
            label={t("settings.idle.delete")}
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
{/if}
