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

  let { api } = $props();

  const FIELDS = `
    key name signup nickname email emailVerified phone phoneVerified
    passwordMinimum refuseCommonPasswords firstFactors secondFactors secondFactorRequired
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
    $secondFactorRequired: Boolean, $emailDomains: [String!], $providers: [String!],
    $everyProvider: Boolean, $confirmation: String, $hidden: Boolean, $signupScopes: [String!]
  `;

  const PASS = `
    key: $key, name: $name, signup: $signup, nickname: $nickname, email: $email,
    emailVerified: $emailVerified, phone: $phone, phoneVerified: $phoneVerified,
    passwordMinimum: $passwordMinimum, refuseCommonPasswords: $refuseCommonPasswords,
    firstFactors: $firstFactors, secondFactors: $secondFactors,
    secondFactorRequired: $secondFactorRequired, emailDomains: $emailDomains,
    providers: $providers, everyProvider: $everyProvider, confirmation: $confirmation,
    hidden: $hidden, signupScopes: $signupScopes
  `;

  const PRESENCE = [
    ["off", "Off"],
    ["optional", "Optional"],
    ["required", "Required"],
  ];

  const FIRST = [
    ["password", "Password"],
    ["passkey", "Passkey"],
    ["provider", "Provider"],
  ];

  const SECOND = [
    ["otp", "Authenticator app"],
    ["passkey", "Passkey"],
    ["backup_codes", "Backup codes"],
    ["email", "Email codes"],
    ["sms", "Text message codes"],
    ["trusted_device", "Approval from a trusted device"],
  ];

  const CONFIRMATIONS = [
    ["none", "None"],
    ["code", "Emailed code"],
    ["link", "Emailed link"],
    ["approval", "Manager approval"],
  ];

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
      fresh ? `${draft.name} added.` : `${draft.name} saved.`,
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
      policy.signup ? "signup open" : "invitation only",
      policy.secondFactorRequired ? "second factor required" : null,
      policy.confirmation !== "none" ? `confirmed by ${policy.confirmation}` : null,
      policy.phone === "required" ? "phone required" : null,
      policy.hidden ? "hidden accounts" : null,
    ]
      .filter(Boolean)
      .join(" · ");

  const signingProviders = $derived(data?.providers ?? []);
</script>

<Page title="Policies">
  {#snippet actions()}
    {#if editing === null}
      <button type="button" class="btn btn-primary btn-sm" onclick={add}>Add policy</button>
    {/if}
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if loading && !data}
    <Spinner />
  {:else if data}
    {#if editing !== null}
      <Section title={editing === "" ? "New policy" : draft.name}>
        <div class="grid gap-3 sm:grid-cols-[2fr_1fr]">
          <Field label="Name" value={draft.name} oninput={(event) => named(event.currentTarget.value)} placeholder="Customers" />
          <Field
            label="Key"
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
            <span class="legend">Sign up</span>
            <div class="policy-controls">
              <Switch label="Open" bind:checked={draft.signup} />

              {#if draft.signup}
                <div class="grid gap-3 sm:grid-cols-2">
                  <Field
                    label="Email domains"
                    bind:value={draft.emailDomains}
                    autocapitalize="none"
                    spellcheck="false"
                    placeholder="any"
                  />

                  <label class="flex flex-col gap-1.5">
                    <span class="text-xs font-medium opacity-70">Confirmation</span>
                    <select class="select select-sm w-full" bind:value={draft.confirmation}>
                      {#each CONFIRMATIONS as [value, label] (value)}
                        <option {value}>{label}</option>
                      {/each}
                    </select>
                  </label>
                </div>

                {#if (draft.confirmation === "code" || draft.confirmation === "link") && !data.tenant.mails}
                  <p class="text-xs text-warning">
                    No mail adapter. <Link to="/adapters" class="link">Add one</Link>
                  </p>
                {/if}

                <div class="flex flex-col gap-1.5">
                  <span class="text-xs font-medium opacity-70">Signup scopes</span>
                  <ScopesEditor
                    value={draft.signupScopes}
                    available={data.scopesSupported.filter((scope) => !scope.startsWith("masks:"))}
                    onchange={(scopes) => (draft.signupScopes = scopes)}
                  />
                </div>
              {/if}

              <Switch label="Hide who has an account" bind:checked={draft.hidden} />

              {#if draft.hidden}
                <p class="text-xs opacity-70">
                  An email address is sent a code before anything else, whether it has an account or not, and a
                  device that account has used before skips it. Nicknames sign in as they always have.
                </p>
                {#if !data.tenant.mails}
                  <p class="text-xs text-warning">
                    No mail adapter, so nobody can sign in with an email address. <Link to="/adapters" class="link">Add one</Link>
                  </p>
                {/if}
              {:else if draft.signup}
                <p class="text-xs text-warning">
                  An unknown address goes straight to signup, which tells anybody which addresses have accounts here.
                </p>
              {/if}
            </div>
          </div>

          <div class="policy-row">
            <span class="legend">Account</span>
            <div class="policy-controls">
              <div class="grid gap-3 sm:grid-cols-3">
                {#each [["nickname", "Nickname"], ["email", "Email"], ["phone", "Phone"]] as [field, label] (field)}
                  <label class="flex flex-col gap-1.5">
                    <span class="text-xs font-medium opacity-70">{label}</span>
                    <select class="select select-sm w-full" bind:value={draft[field]}>
                      {#each PRESENCE as [value, text] (value)}
                        <option {value}>{text}</option>
                      {/each}
                    </select>
                  </label>
                {/each}
              </div>

              <div class="flex flex-wrap gap-x-5 gap-y-2">
                <Switch label="Confirmed email" bind:checked={draft.emailVerified} />
                <Switch label="Confirmed phone" bind:checked={draft.phoneVerified} />
              </div>

              {#if draft.phone !== "off" && draft.phoneVerified && !data.tenant.texts}
                <p class="text-xs text-warning">
                  No SMS adapter. <Link to="/adapters" class="link">Add one</Link>
                </p>
              {/if}
            </div>
          </div>

          <div class="policy-row">
            <span class="legend">Sign in</span>
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
                    characters minimum
                  </label>
                  <Switch label="Refuse common passwords" bind:checked={draft.refuseCommonPasswords} />
                </div>
              {/if}

              {#if draft.firstFactors.includes("provider") && signingProviders.length}
                <div class="flex flex-wrap gap-x-5 gap-y-2">
                  <Switch
                    label="All providers"
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
            <span class="legend">Second factor</span>
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

              <Switch label="Required for everyone, not just managers" bind:checked={draft.secondFactorRequired} />
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
            {editing === "" ? "Add" : "Save"}
          </button>
          <button type="button" class="btn btn-ghost btn-sm" onclick={close}>Cancel</button>
        </div>
      </Section>
    {/if}

    <Section>
      {#if data.active.length === 0}
        <p class="text-sm opacity-70">None yet. Clients use the built-in default.</p>
      {/if}

      {#each data.active as policy (policy.key)}
        <div class="flex flex-wrap items-start justify-between gap-2 border-b border-base-300 pb-3 last:border-0 last:pb-0">
          <div class="flex min-w-0 flex-col gap-1">
            <span class="font-medium">
              {policy.name}
              {#if policy.default}<span class="badge badge-success badge-sm">Default</span>{/if}
            </span>
            <span class="text-xs opacity-60">{summary(policy)}</span>
            {#if policy.clients.length}
              <span class="text-xs opacity-60">
                Used by
                {#each policy.clients as client, index (client.clientId)}
                  {index ? ", " : ""}<Link to={`/clients/${client.clientId}`} class="link">{client.name}</Link>
                {/each}
              </span>
            {/if}
          </div>

          <div class="flex gap-2">
            <button type="button" class="btn btn-sm" onclick={() => edit(policy)}>Edit</button>
            {#if !policy.default}
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                onclick={() =>
                  act(
                    "archiveSignInPolicy",
                    policy,
                    `${policy.name} is archived.`,
                    `Archive ${policy.name}? Its clients go back to the default.`,
                  )}
              >
                Archive
              </button>
            {/if}
          </div>
        </div>
      {/each}
    </Section>

    {#if data.archived.length}
      <Section title="Archived">
        {#each data.archived as policy (policy.key)}
          <div class="flex items-center justify-between gap-2">
            <span class="text-sm">{policy.name}</span>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              onclick={() => act("restoreSignInPolicy", policy, `${policy.name} is back.`)}
            >
              Restore
            </button>
          </div>
        {/each}
      </Section>
    {/if}
  {/if}
</Page>
