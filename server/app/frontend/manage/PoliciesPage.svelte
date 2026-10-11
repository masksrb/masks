<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import ScopesEditor from "./ScopesEditor.svelte";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";
  import Switch from "./ui/Switch.svelte";
  import { t } from "./lib/copy.js";
  import { duration } from "./lib/policies.js";

  let { api } = $props();

  const FIELDS = `
    key name signup nickname email emailVerified phone phoneVerified
    passwordMinimum refuseCommonPasswords firstFactors secondFactors secondFactorRequired appsRequireSecondFactor
    sessionLifetime sessionIdleTimeout refuseBreachedPasswords riskStepUpAt riskRefuseAt
    emailDomains providers confirmation hidden signupScopes default archivedAt
    clients { clientId name }
  `;

  const QUERY = `
    query Policies {
      active: signInPolicies { ${FIELDS} }
      archived: signInPolicies(archived: true) { ${FIELDS} }
      providers { key name }
      tenant { namedBy texts mails }
      scopesSupported
    }
  `;

  const ARGS = `
    $key: ID!, $name: String, $signup: Boolean, $nickname: String, $email: String,
    $emailVerified: Boolean, $phone: String, $phoneVerified: Boolean, $passwordMinimum: Int,
    $refuseCommonPasswords: Boolean, $firstFactors: [String!], $secondFactors: [String!],
    $secondFactorRequired: Boolean, $appsRequireSecondFactor: Boolean,
    $sessionLifetime: Int, $sessionIdleTimeout: Int,
    $refuseBreachedPasswords: Boolean, $riskStepUpAt: Int, $riskRefuseAt: Int, $emailDomains: [String!], $providers: [String!],
    $everyProvider: Boolean, $confirmation: String, $hidden: Boolean, $signupScopes: [String!]
  `;

  const PASS = `
    key: $key, name: $name, signup: $signup, nickname: $nickname, email: $email,
    emailVerified: $emailVerified, phone: $phone, phoneVerified: $phoneVerified,
    passwordMinimum: $passwordMinimum, refuseCommonPasswords: $refuseCommonPasswords,
    firstFactors: $firstFactors, secondFactors: $secondFactors,
    secondFactorRequired: $secondFactorRequired, appsRequireSecondFactor: $appsRequireSecondFactor,
    sessionLifetime: $sessionLifetime, sessionIdleTimeout: $sessionIdleTimeout,
    refuseBreachedPasswords: $refuseBreachedPasswords, riskStepUpAt: $riskStepUpAt, riskRefuseAt: $riskRefuseAt, emailDomains: $emailDomains,
    providers: $providers, everyProvider: $everyProvider, confirmation: $confirmation,
    hidden: $hidden, signupScopes: $signupScopes
  `;

  const HOUR = 3600;
  const DAY = 24 * HOUR;

  const LIFETIMES = [
    [null, t("policy_rules.values.default_lifetime")],
    ...[HOUR, 8 * HOUR, 12 * HOUR, DAY, 7 * DAY, 30 * DAY, 90 * DAY].map((seconds) => [seconds, duration(seconds)]),
  ];

  const IDLE = [
    [null, t("policies.never")],
    ...[15 * 60, 30 * 60, HOUR, 4 * HOUR, DAY].map((seconds) => [seconds, duration(seconds)]),
  ];

  const SCORES = [[null, t("policies.never")], ...[30, 50, 70, 90].map((score) => [score, t("policies.score", { score })])];

  const offered = (choices, value) =>
    value === null || choices.some(([held]) => held === value)
      ? choices
      : [...choices, [value, t("policy_rules.units.second", { count: value })]];

  const labelled = (group, values) => values.map((value) => [value, t(`policies.${group}.${value}`)]);

  const PRESENCE = labelled("presence", ["off", "optional", "required"]);

  const FIRST = labelled("first", ["password", "passkey", "provider", "email_code"]);

  const SECOND = labelled("second", ["otp", "passkey", "backup_codes", "email", "sms", "trusted_device"]);

  const CONFIRMATIONS = labelled("confirmations", ["none", "code", "link", "approval"]);

  const ACCOUNT_FIELDS = ["nickname", "email", "phone"].map((field) => [field, t(`policies.form.account.${field}`)]);

  const BLANK = {
    key: "",
    name: "",
    signup: false,
    nickname: "optional",
    email: "required",
    emailVerified: false,
    phone: "off",
    phoneVerified: false,
    passwordMinimum: 8,
    refuseCommonPasswords: true,
    firstFactors: ["password", "passkey", "provider"],
    secondFactors: ["otp", "passkey", "backup_codes"],
    secondFactorRequired: false,
    appsRequireSecondFactor: false,
    sessionLifetime: null,
    sessionIdleTimeout: null,
    refuseBreachedPasswords: false,
    riskStepUpAt: null,
    riskRefuseAt: null,
    emailDomains: "",
    providers: null,
    confirmation: "none",
    hidden: false,
    signupScopes: [],
  };

  const feedback = createFeedback();

  let data = $state(null);
  let loading = $state(true);
  let busy = $state(false);
  let editing = $state(null);
  let draft = $state({ ...BLANK });

  async function load() {
    loading = true;

    const answer = await feedback.attempt(() => api.query(QUERY));

    loading = false;

    if (answer) data = answer;
  }

  load();

  function add() {
    editing = "";
    keyTouched = false;
    draft = structuredClone(BLANK);
    feedback.clear();
  }

  function edit(policy) {
    editing = policy.key;
    draft = {
      ...structuredClone($state.snapshot(policy)),
      emailDomains: policy.emailDomains.join(" "),
    };
    feedback.clear();
  }

  const slug = (name) =>
    name
      .toLowerCase()
      .normalize("NFKD")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");

  let keyTouched = $state(false);

  function named(name) {
    draft.name = name;
    if (editing === "" && !keyTouched) draft.key = slug(name);
  }

  function close() {
    editing = null;
    feedback.clear();
  }

  const toggle = (list, value, on) =>
    on ? [...new Set([...list, value])] : list.filter((held) => held !== value);

  function variables() {
    return {
      key: draft.key.trim(),
      name: draft.name.trim(),
      signup: draft.signup,
      nickname: draft.nickname,
      email: draft.email,
      emailVerified: draft.emailVerified,
      phone: draft.phone,
      phoneVerified: draft.phoneVerified,
      passwordMinimum: Number(draft.passwordMinimum) || 8,
      refuseCommonPasswords: draft.refuseCommonPasswords,
      firstFactors: draft.firstFactors,
      secondFactors: draft.secondFactors,
      secondFactorRequired: draft.secondFactorRequired,
      appsRequireSecondFactor: draft.appsRequireSecondFactor,
      sessionLifetime: draft.sessionLifetime,
      sessionIdleTimeout: draft.sessionIdleTimeout,
      refuseBreachedPasswords: draft.refuseBreachedPasswords,
      riskStepUpAt: draft.riskStepUpAt,
      riskRefuseAt: draft.riskRefuseAt,
      emailDomains: draft.emailDomains.split(/[\s,]+/).filter(Boolean),
      providers: draft.providers ?? [],
      everyProvider: draft.providers === null,
      confirmation: draft.confirmation,
      hidden: draft.hidden,
      signupScopes: draft.signupScopes,
    };
  }

  async function save() {
    busy = true;

    const fresh = editing === "";
    const done = await feedback.attempt(
      () =>
        api.query(
          fresh
            ? `mutation Create(${ARGS}) { createSignInPolicy(${PASS}) { signInPolicy { key } } }`
            : `mutation Update(${ARGS}) { updateSignInPolicy(${PASS}) { signInPolicy { key } } }`,
          variables(),
        ),
      fresh ? t("policies.added", { name: draft.name }) : t("policies.saved", { name: draft.name }),
    );

    busy = false;

    if (!done) return;

    editing = null;
    await load();
  }

  async function act(mutation, policy, notice, question = null) {
    if (question && !confirm(question)) return;

    const done = await feedback.attempt(
      () =>
        api.query(`mutation Act($key: ID!) { ${mutation}(key: $key) { signInPolicy { key } } }`, {
          key: policy.key,
        }),
      notice,
    );

    if (done) await load();
  }

  const summary = (policy) =>
    [
      policy.signup ? t("policies.summary.signup_open") : t("policies.summary.invitation_only"),
      policy.secondFactorRequired ? t("policies.summary.second_factor_required") : null,
      policy.appsRequireSecondFactor ? t("policies.summary.apps_require_second_factor") : null,
      policy.sessionLifetime ? t("policies.summary.lifetime", { duration: duration(policy.sessionLifetime) }) : null,
      policy.sessionIdleTimeout ? t("policies.summary.idle", { duration: duration(policy.sessionIdleTimeout) }) : null,
      policy.confirmation !== "none" ? t("policies.summary.confirmed_by", { confirmation: policy.confirmation }) : null,
      policy.phone === "required" ? t("policies.summary.phone_required") : null,
      policy.hidden ? t("policies.summary.hidden") : null,
    ]
      .filter(Boolean)
      .join(" · ");

  const signingProviders = $derived(data?.providers ?? []);
</script>

<Page title={t("policies.title")}>
  {#snippet actions()}
    {#if editing === null}
      <button type="button" class="btn btn-primary btn-sm" onclick={add}>{t("policies.add")}</button>
    {/if}
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if loading && !data}
    <Spinner />
  {:else if data}
    {#if editing !== null}
      <Section title={editing === "" ? t("policies.form.new") : draft.name}>
        <div class="grid gap-3 sm:grid-cols-[2fr_1fr]">
          <Field
            label={t("policies.form.name")}
            value={draft.name}
            oninput={(event) => named(event.currentTarget.value)}
            placeholder={t("policies.form.name_placeholder")}
          />
          <Field
            label={t("policies.form.key")}
            bind:value={draft.key}
            oninput={() => (keyTouched = true)}
            disabled={editing !== ""}
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
            class="input input-sm w-full font-mono"
          />
        </div>

        <div class="policy-rows">
          <div class="policy-row">
            <span class="legend">{t("policies.form.signup.legend")}</span>
            <div class="policy-controls">
              <Switch label={t("policies.form.signup.open")} bind:checked={draft.signup} />

              {#if draft.signup}
                <div class="grid gap-3 sm:grid-cols-2">
                  <Field
                    label={t("policies.form.signup.email_domains")}
                    bind:value={draft.emailDomains}
                    autocapitalize="none"
                    spellcheck="false"
                    placeholder={t("policies.form.signup.email_domains_placeholder")}
                  />

                  <label class="flex flex-col gap-1.5">
                    <span class="field-label">{t("policies.form.signup.confirmation")}</span>
                    <select class="select select-sm w-full" bind:value={draft.confirmation}>
                      {#each CONFIRMATIONS as [value, label] (value)}
                        <option {value}>{label}</option>
                      {/each}
                    </select>
                  </label>
                </div>

                {#if (draft.confirmation === "code" || draft.confirmation === "link") && !data.tenant.mails}
                  <p class="text-xs text-warning">
                    {t("policies.form.signup.no_mail")} <Link to="/adapters" class="link">{t("policies.form.add_one")}</Link>
                  </p>
                {/if}

                <div class="flex flex-col gap-1.5">
                  <span class="field-label">{t("policies.form.signup.scopes")}</span>
                  <ScopesEditor
                    value={draft.signupScopes}
                    available={data.scopesSupported.filter((scope) => !scope.startsWith("masks:"))}
                    onchange={(scopes) => (draft.signupScopes = scopes)}
                  />
                </div>
              {/if}

              <Switch label={t("policies.form.signup.hidden")} bind:checked={draft.hidden} />

              {#if draft.hidden}
                <p class="text-xs opacity-85">
                  {t("policies.form.signup.hidden_hint")}
                </p>
                {#if !data.tenant.mails}
                  <p class="text-xs text-warning">
                    {t("policies.form.signup.hidden_no_mail")}
                    <Link to="/adapters" class="link">{t("policies.form.add_one")}</Link>
                  </p>
                {/if}
              {:else if draft.signup}
                <p class="text-xs text-warning">
                  {t("policies.form.signup.open_warning")}
                </p>
              {/if}
            </div>
          </div>

          <div class="policy-row">
            <span class="legend">{t("policies.form.account.legend")}</span>
            <div class="policy-controls">
              <div class="grid gap-3 sm:grid-cols-3">
                {#each ACCOUNT_FIELDS as [field, label] (field)}
                  <label class="flex flex-col gap-1.5">
                    <span class="field-label">{label}</span>
                    <select class="select select-sm w-full" bind:value={draft[field]}>
                      {#each PRESENCE as [value, text] (value)}
                        <option {value}>{text}</option>
                      {/each}
                    </select>
                  </label>
                {/each}
              </div>

              <div class="flex flex-wrap gap-x-5 gap-y-2">
                <Switch label={t("policies.form.account.email_verified")} bind:checked={draft.emailVerified} />
                <Switch label={t("policies.form.account.phone_verified")} bind:checked={draft.phoneVerified} />
              </div>

              {#if draft.phone !== "off" && draft.phoneVerified && !data.tenant.texts}
                <p class="text-xs text-warning">
                  {t("policies.form.account.no_sms")} <Link to="/adapters" class="link">{t("policies.form.add_one")}</Link>
                </p>
              {/if}
            </div>
          </div>

          <div class="policy-row">
            <span class="legend">{t("policies.form.sign_in.legend")}</span>
            <div class="policy-controls">
              <div class="flex flex-wrap gap-x-5 gap-y-2">
                {#each FIRST as [value, label] (value)}
                  <Switch
                    label={label}
                    checked={draft.firstFactors.includes(value)}
                    onchange={(on) => (draft.firstFactors = toggle(draft.firstFactors, value, on))}
                  />
                {/each}
              </div>

              {#if draft.firstFactors.includes("password")}
                <div class="flex flex-wrap items-center gap-x-5 gap-y-2">
                  <label class="flex items-center gap-2 text-sm">
                    <input class="input input-sm w-16" type="number" min="8" bind:value={draft.passwordMinimum} />
                    {t("policies.form.sign_in.characters")}
                  </label>
                  <Switch label={t("policies.form.sign_in.refuse_common")} bind:checked={draft.refuseCommonPasswords} />
                </div>
              {/if}

              {#if draft.firstFactors.includes("provider") && signingProviders.length}
                <div class="flex flex-wrap gap-x-5 gap-y-2">
                  <Switch
                    label={t("policies.form.sign_in.all_providers")}
                    checked={draft.providers === null}
                    onchange={(on) => (draft.providers = on ? null : signingProviders.map((held) => held.key))}
                  />

                  {#if draft.providers !== null}
                    {#each signingProviders as provider (provider.key)}
                      <Switch
                        label={provider.name}
                        checked={draft.providers.includes(provider.key)}
                        onchange={(on) => (draft.providers = toggle(draft.providers, provider.key, on))}
                      />
                    {/each}
                  {/if}
                </div>
              {/if}
            </div>
          </div>

          <div class="policy-row">
            <span class="legend">{t("policies.form.second_factor.legend")}</span>
            <div class="policy-controls">
              <div class="flex flex-wrap gap-x-5 gap-y-2">
                {#each SECOND as [value, label] (value)}
                  <Switch
                    label={label}
                    checked={draft.secondFactors.includes(value)}
                    onchange={(on) => (draft.secondFactors = toggle(draft.secondFactors, value, on))}
                  />
                {/each}
              </div>

              <Switch label={t("policies.form.second_factor.required")} bind:checked={draft.secondFactorRequired} />
              <Switch
                label={t("policies.form.second_factor.apps")}
                bind:checked={draft.appsRequireSecondFactor}
              />
            </div>
          </div>

          <div class="policy-row">
            <span class="legend">{t("policies.form.risk.legend")}</span>
            <div class="policy-controls">
              <div class="flex flex-wrap items-center gap-x-5 gap-y-2">
                <label class="flex items-center gap-2 text-sm">
                  {t("policies.form.risk.step_up")}
                  <select class="select select-sm w-auto" bind:value={draft.riskStepUpAt}>
                    {#each offered(SCORES, draft.riskStepUpAt) as [value, label] (value)}
                      <option {value}>{label}</option>
                    {/each}
                  </select>
                </label>
                <label class="flex items-center gap-2 text-sm">
                  {t("policies.form.risk.refuse")}
                  <select class="select select-sm w-auto" bind:value={draft.riskRefuseAt}>
                    {#each offered(SCORES, draft.riskRefuseAt) as [value, label] (value)}
                      <option {value}>{label}</option>
                    {/each}
                  </select>
                </label>
              </div>
              <Switch label={t("policies.form.risk.refuse_breached")} bind:checked={draft.refuseBreachedPasswords} />
              <p class="hint">
                {t("policies.form.risk.hint")}
              </p>
            </div>
          </div>

          <div class="policy-row">
            <span class="legend">{t("policies.form.sessions.legend")}</span>
            <div class="policy-controls">
              <div class="flex flex-wrap items-center gap-x-5 gap-y-2">
                <label class="flex items-center gap-2 text-sm">
                  {t("policies.form.sessions.last")}
                  <select class="select select-sm w-auto" bind:value={draft.sessionLifetime}>
                    {#each offered(LIFETIMES, draft.sessionLifetime) as [value, label] (value)}
                      <option {value}>{label}</option>
                    {/each}
                  </select>
                  {t("policies.form.sessions.after_sign_in")}
                </label>
                <label class="flex items-center gap-2 text-sm">
                  {t("policies.form.sessions.end_after")}
                  <select class="select select-sm w-auto" bind:value={draft.sessionIdleTimeout}>
                    {#each offered(IDLE, draft.sessionIdleTimeout) as [value, label] (value)}
                      <option {value}>{label}</option>
                    {/each}
                  </select>
                  {t("policies.form.sessions.idle")}
                </label>
              </div>
              <p class="hint">
                {t("policies.form.sessions.hint")}
              </p>
            </div>
          </div>
        </div>

        <div class="flex gap-2">
          <button
            type="button"
            class="btn btn-primary btn-sm"
            disabled={busy || !draft.key.trim() || !draft.name.trim()}
            onclick={save}
          >
            {editing === "" ? t("policies.form.create") : t("policies.form.save")}
          </button>
          <button type="button" class="btn btn-ghost btn-sm" onclick={close}>{t("policies.form.cancel")}</button>
        </div>
      </Section>
    {/if}

    <Section>
      {#if data.active.length === 0}
        <p class="text-sm opacity-85">{t("policies.list.empty")}</p>
      {/if}

      {#each data.active as policy (policy.key)}
        <div class="flex flex-wrap items-start justify-between gap-2 border-b border-base-300 pb-3 last:border-0 last:pb-0">
          <div class="flex min-w-0 flex-col gap-1">
            <span class="font-medium">
              {policy.name}
              {#if policy.default}<span class="badge badge-success badge-sm">{t("policies.list.default")}</span>{/if}
            </span>
            <span class="hint">{summary(policy)}</span>
            {#if policy.clients.length}
              <span class="hint">
                {t("policies.list.used_by")}
                {#each policy.clients as client, index (client.clientId)}
                  {index ? ", " : ""}<Link to={`/clients/${client.clientId}`} class="link">{client.name}</Link>
                {/each}
              </span>
            {/if}
          </div>

          <div class="flex gap-2">
            <button type="button" class="btn btn-sm" onclick={() => edit(policy)}>{t("policies.list.edit")}</button>
            {#if !policy.default}
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                onclick={() =>
                  act(
                    "archiveSignInPolicy",
                    policy,
                    t("policies.archived_notice", { name: policy.name }),
                    t("policies.archive_confirm", { name: policy.name }),
                  )}
              >
                {t("policies.list.archive")}
              </button>
            {/if}
          </div>
        </div>
      {/each}
    </Section>

    {#if data.archived.length}
      <Section title={t("policies.archived.title")}>
        {#each data.archived as policy (policy.key)}
          <div class="flex items-center justify-between gap-2">
            <span class="text-sm">{policy.name}</span>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              onclick={() => act("restoreSignInPolicy", policy, t("policies.restored", { name: policy.name }))}
            >
              {t("policies.archived.restore")}
            </button>
          </div>
        {/each}
      </Section>
    {/if}
  {/if}
</Page>
