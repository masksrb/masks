<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import ScopesEditor from "./ScopesEditor.svelte";
  import Card from "./ui/Card.svelte";
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
      providers { key name signsIn }
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
    ["off", "Not asked"],
    ["optional", "Optional"],
    ["required", "Required"],
  ];

  const FIRST = [
    ["password", "Password"],
    ["passkey", "Passkey"],
    ["provider", "A connected provider"],
  ];

  const SECOND = [
    ["otp", "Authenticator app"],
    ["passkey", "Passkey"],
    ["backup_codes", "Backup codes"],
  ];

  const CONFIRMATIONS = [
    ["none", "None — the account works at once"],
    ["code", "A code emailed to them, entered on the spot"],
    ["link", "A link emailed to them"],
    ["approval", "A manager approves it"],
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
      policy.hidden ? "hides who has an account" : null,
    ]
      .filter(Boolean)
      .join(" · ");

  const signingProviders = $derived((data?.providers ?? []).filter((held) => held.signsIn));
</script>

<Page
  title="Policies"
  lede="What a person needs to sign in to a client, and whether they can sign up there. A client follows the tenant's default unless it names its own."
>
  {#snippet actions()}
    <button type="button" class="btn btn-primary btn-sm" onclick={add}>Add a policy</button>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if loading && !data}
    <Spinner />
  {:else if data}
    {#if editing !== null}
      <Card title={editing === "" ? "Add a policy" : `Edit ${draft.name}`}>
        <div class="grid gap-3 sm:grid-cols-2">
          <Field
            label="Key"
            bind:value={draft.key}
            disabled={editing !== ""}
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
            placeholder="customers"
          />
          <Field label="Name" bind:value={draft.name} placeholder="Customers" />
        </div>

        <div class="flex flex-col gap-3 rounded-lg bg-base-200 p-3">
          <span class="legend">Signing up</span>

          <Switch label="Somebody new can create an account" bind:checked={draft.signup} />

          {#if draft.signup}
            <Field
              label="Only addresses at these domains (blank for any)"
              bind:value={draft.emailDomains}
              autocapitalize="none"
              spellcheck="false"
              placeholder="example.com"
            />

            <label class="flex flex-col gap-1.5">
              <span class="text-xs font-medium opacity-70">A new account is confirmed by</span>
              <select class="select select-sm w-full" bind:value={draft.confirmation}>
                {#each CONFIRMATIONS as [value, label] (value)}
                  <option {value}>{label}</option>
                {/each}
              </select>
            </label>

            {#if (draft.confirmation === "code" || draft.confirmation === "link") && !data.tenant.mails}
              <p class="text-xs text-warning">
                Nothing can be emailed yet. <Link to="/adapters" class="link">Add a mail adapter</Link>.
              </p>
            {/if}

            <div class="flex flex-col gap-1">
              <span class="text-xs font-medium opacity-70">Scopes a new account holds</span>
              <ScopesEditor
                value={draft.signupScopes}
                available={data.scopesSupported.filter((scope) => !scope.startsWith("masks:"))}
                onchange={(scopes) => (draft.signupScopes = scopes)}
              />
            </div>

            <label class="flex items-start gap-3 text-sm">
              <input type="checkbox" class="toggle toggle-sm" bind:checked={draft.hidden} />
              <span>
                Do not reveal who has an account
                <span class="block text-xs opacity-60">
                  An email address always gets a code first, account or not, so the screens only
                  differ once the inbox is proven. Off, signing up after an unknown address shows
                  that no account exists for it.
                </span>
              </span>
            </label>
          {/if}
        </div>

        <div class="flex flex-col gap-3 rounded-lg bg-base-200 p-3">
          <span class="legend">What an account has</span>

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

          <Switch label="The email has to be confirmed" bind:checked={draft.emailVerified} />
          <Switch label="The phone has to be confirmed by a text" bind:checked={draft.phoneVerified} />

          {#if draft.phone !== "off" && draft.phoneVerified && !data.tenant.texts}
            <p class="text-xs text-warning">
              No texts can be sent yet. <Link to="/adapters" class="link">Add an SMS adapter</Link>.
            </p>
          {/if}

          <p class="text-xs opacity-60">
            This tenant names accounts by {data.tenant.namedBy}. Somebody who already has an
            account is asked for whatever is missing the next time they sign in here.
          </p>
        </div>

        <div class="flex flex-col gap-3 rounded-lg bg-base-200 p-3">
          <span class="legend">Signing in</span>

          <div class="flex flex-wrap gap-4">
            {#each FIRST as [value, label] (value)}
              <label class="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  class="toggle toggle-sm"
                  checked={draft.firstFactors.includes(value)}
                  onchange={(event) =>
                    (draft.firstFactors = toggle(draft.firstFactors, value, event.currentTarget.checked))}
                />
                {label}
              </label>
            {/each}
          </div>

          <div class="grid gap-3 sm:grid-cols-2">
            <Field label="Shortest password" type="number" bind:value={draft.passwordMinimum} min="8" />
          </div>

          <Switch label="Refuse common passwords" bind:checked={draft.refuseCommonPasswords} />

          {#if draft.firstFactors.includes("provider") && signingProviders.length}
            <div class="flex flex-col gap-2">
              <Switch
                label="Offer every provider that signs people in"
                checked={draft.providers === null}
                onchange={(on) => (draft.providers = on ? null : signingProviders.map((held) => held.key))}
              />

              {#if draft.providers !== null}
                <div class="flex flex-wrap gap-4">
                  {#each signingProviders as provider (provider.key)}
                    <label class="flex items-center gap-2 text-sm">
                      <input
                        type="checkbox"
                        class="toggle toggle-sm"
                        checked={draft.providers.includes(provider.key)}
                        onchange={(event) =>
                          (draft.providers = toggle(draft.providers, provider.key, event.currentTarget.checked))}
                      />
                      {provider.name}
                    </label>
                  {/each}
                </div>
              {/if}
            </div>
          {/if}
        </div>

        <div class="flex flex-col gap-3 rounded-lg bg-base-200 p-3">
          <span class="legend">Second factors</span>

          <div class="flex flex-wrap gap-4">
            {#each SECOND as [value, label] (value)}
              <label class="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  class="toggle toggle-sm"
                  checked={draft.secondFactors.includes(value)}
                  onchange={(event) =>
                    (draft.secondFactors = toggle(draft.secondFactors, value, event.currentTarget.checked))}
                />
                {label}
              </label>
            {/each}
          </div>

          <Switch label="Everybody needs at least one" bind:checked={draft.secondFactorRequired} />

          <p class="text-xs opacity-60">Managers always need one, whatever this says.</p>
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
      </Card>
    {/if}

    <Card>
      {#if data.active.length === 0}
        <p class="text-sm opacity-70">
          No policies yet. Every client follows masks' built-in default: invitation only, a password or
          passkey, and a second factor for managers.
        </p>
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
                    `Archive ${policy.name}? Clients using it fall back to the tenant's default.`,
                  )}
              >
                Archive
              </button>
            {/if}
          </div>
        </div>
      {/each}
    </Card>

    {#if data.archived.length}
      <Card title="Archived">
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
      </Card>
    {/if}
  {/if}
</Page>
