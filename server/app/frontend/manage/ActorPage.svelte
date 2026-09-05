<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, since } from "./lib/format.js";
  import ScopesEditor from "./ScopesEditor.svelte";
  import Card from "./ui/Card.svelte";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api, uuid } = $props();

  const FIELDS = [
    ["name", "Name"],
    ["givenName", "Given name"],
    ["familyName", "Family name"],
    ["middleName", "Middle name"],
    ["email", "Email"],
    ["profileUrl", "Profile URL"],
    ["pictureUrl", "Picture URL"],
    ["websiteUrl", "Website"],
    ["gender", "Gender"],
    ["birthdate", "Birthdate"],
    ["zoneinfo", "Time zone"],
    ["locale", "Locale"],
  ];

  const QUERY = `
    query Actor($uuid: ID!) {
      actor(uuid: $uuid) {
        uuid nickname email emailVerified scopes otpEnabled backupCodesRemaining
        backupCodesGeneratedAt lastLoginAt createdAt activated invitedAt
        passkeys { id label aaguid certification compromise userVerified lastUsedAt }
        name givenName familyName middleName profileUrl pictureUrl websiteUrl
        gender birthdate zoneinfo locale
      }
      scopesSupported
    }
  `;

  const feedback = createFeedback();

  let actor = $state(null);
  let supported = $state([]);
  let draft = $state({});
  let loading = $state(true);
  let codes = $state(null);
  let link = $state(null);

  async function load() {
    loading = true;

    try {
      const data = await api.query(QUERY, { uuid });

      actor = data.actor;
      supported = data.scopesSupported;
      draft = Object.fromEntries(FIELDS.map(([key]) => [key, data.actor?.[key] ?? ""]));
    } catch (thrown) {
      feedback.blame(thrown);
    } finally {
      loading = false;
    }
  }

  load();

  async function act(document, variables, notice) {
    const data = await feedback.attempt(() => api.query(document, variables), notice);

    if (data) await load();

    return data;
  }

  const saveProfile = () =>
    act(
      `mutation Save($uuid: ID!, ${FIELDS.map(([key]) => `$${key}: String`).join(", ")}) {
        updateActor(uuid: $uuid, ${FIELDS.map(([key]) => `${key}: $${key}`).join(", ")}) { actor { uuid } }
      }`,
      {
        uuid,
        ...Object.fromEntries(
          Object.entries(draft).map(([key, value]) => [key, value === "" ? null : value]),
        ),
      },
      "Profile saved.",
    );

  const saveScopes = (scopes) =>
    act(
      `mutation Scopes($uuid: ID!, $scopes: [String!]!) {
        setActorScopes(uuid: $uuid, scopes: $scopes) { actor { scopes } }
      }`,
      { uuid, scopes },
      "Scopes updated.",
    );

  async function generate() {
    codes = null;

    const data = await act(
      `mutation Codes($uuid: ID!) { generateBackupCodes(uuid: $uuid) { codes } }`,
      { uuid },
      "Backup codes generated. They are shown once and never again.",
    );

    if (data) codes = data.generateBackupCodes.codes;
  }

  async function recover(document, confirmation) {
    if (!confirm(confirmation)) return;

    link = null;

    const data = await act(document, { uuid }, null);

    if (!data) return;

    const result = Object.values(data)[0];

    if (result.delivered) {
      feedback.say("Emailed. The link is not shown here, so that using it proves the address.");
    } else {
      feedback.say("No mailer is configured, so pass this link along yourself. It works once.");
      link = result.url;
    }
  }

  const reset = () =>
    recover(
      `mutation Reset($uuid: ID!) { resetPassword(uuid: $uuid) { delivered url } }`,
      "Start a password reset? Every session and refresh token ends when the link is used.",
    );

  const resend = () =>
    recover(
      `mutation Resend($uuid: ID!) { resendInvitation(uuid: $uuid) { delivered url } }`,
      "Send a fresh invitation? The previous one stops working.",
    );

  function revokePasskey(passkey) {
    if (!confirm(`Remove the passkey “${passkey.label}”?`)) return;

    act(
      `mutation Revoke($uuid: ID!, $id: ID!) { revokePasskey(uuid: $uuid, id: $id) { actor { uuid } } }`,
      { uuid, id: passkey.id },
      "Passkey removed.",
    );
  }

  function disable() {
    if (!confirm("Remove this actor's authenticator and every backup code?")) return;

    act(
      `mutation Disable($uuid: ID!) { disableAuthenticator(uuid: $uuid) { actor { otpEnabled } } }`,
      { uuid },
      "Authenticator removed.",
    );
  }
</script>

{#if loading && !actor}
  <Spinner />
{:else if !actor}
  <div class="alert alert-error alert-soft text-sm" role="alert">
    {feedback.state.failure ?? "There is no actor with that uuid."}
  </div>
{:else}
  <Page
    title={actor.nickname}
    id={actor.uuid}
    back={{ to: "/actors", label: "Actors" }}
    lede={actor.activated
      ? `Signed in ${since(actor.lastLoginAt, "never")}.`
      : "Invited, and has not accepted yet."}
  >
    <Notices feedback={feedback.state} />

    {#if link}
      <div class="alert alert-info alert-soft flex-col items-start gap-2" role="status">
        <span class="font-medium">This link works once.</span>
        <code class="font-mono text-xs break-all">{link}</code>
      </div>
    {/if}

    {#if codes}
      <div class="alert alert-warning alert-soft flex-col items-start gap-2" role="status">
        <span class="font-medium">Write these down. They are not recoverable.</span>
        <div class="grid grid-cols-2 gap-2 font-mono text-sm md:grid-cols-5">
          {#each codes as code (code)}<span>{code}</span>{/each}
        </div>
      </div>
    {/if}

    <div class="grid items-start gap-4 md:grid-cols-2">
      <Card
        title="Profile"
        lede="Released to clients under the profile and email scopes, and nowhere else."
      >
        <div class="grid gap-3 sm:grid-cols-2">
          {#each FIELDS as [key, label] (key)}
            <Field {label} bind:value={draft[key]} />
          {/each}
        </div>

        <button type="button" class="btn btn-primary btn-sm self-start" onclick={saveProfile}>
          Save profile
        </button>
      </Card>

      <div class="flex flex-col gap-4">
        <Card
          title="Scopes"
          lede="The ceiling on what any client may be granted on this actor's behalf."
        >
          <ScopesEditor value={actor.scopes} available={supported} onchange={saveScopes} />
        </Card>

        <Card title="Access">
          {#if actor.activated}
            <p class="max-w-prose text-sm opacity-70">
              This account has a password. A reset sends a one-time link and signs it out
              everywhere.
            </p>
            <button type="button" class="btn btn-sm self-start" onclick={reset}>
              Reset password
            </button>
          {:else}
            <p class="max-w-prose text-sm opacity-70">
              Invited{actor.invitedAt ? ` on ${day(actor.invitedAt)}` : ""}, and has not accepted
              yet. There is no password to reset until they do.
            </p>
            <button type="button" class="btn btn-sm self-start" onclick={resend}>
              Resend invitation
            </button>
          {/if}
        </Card>

        <Card
          title="Passkeys"
          lede="A passkey counts as both factors on its own, so each one here is a way in."
        >
          {#if actor.passkeys.length === 0}
            <p class="text-sm opacity-70">None enrolled.</p>
          {:else}
            <ul class="flex flex-col gap-2">
              {#each actor.passkeys as passkey (passkey.id)}
                <li class="flex flex-col gap-1 rounded-lg bg-base-200 px-3 py-2">
                  <div class="flex items-baseline justify-between gap-3">
                    <span class="text-sm font-medium">{passkey.label}</span>
                    <span class="flex items-baseline gap-2">
                      {#if passkey.userVerified}
                        <span class="badge badge-success badge-xs">verifies the person</span>
                      {/if}
                      {#if passkey.certification}
                        <span class="badge badge-ghost badge-xs">{passkey.certification}</span>
                      {/if}
                      <button
                        type="button"
                        class="link text-xs text-error"
                        onclick={() => revokePasskey(passkey)}
                      >
                        Remove
                      </button>
                    </span>
                  </div>

                  {#if passkey.compromise}
                    <span class="text-xs text-error">
                      Compromise reported for this model: {passkey.compromise
                        .toLowerCase()
                        .replaceAll("_", " ")}.
                    </span>
                  {/if}

                  <div class="flex flex-wrap gap-x-4 text-xs opacity-60">
                    <span class="font-mono">{passkey.aaguid ?? "no aaguid"}</span>
                    <span>Last used {since(passkey.lastUsedAt, "never")}</span>
                  </div>
                </li>
              {/each}
            </ul>
          {/if}
        </Card>

        <Card title="Second factor">
          {#if actor.otpEnabled}
            <p class="text-sm">
              Authenticator enabled. {actor.backupCodesRemaining} backup
              code{actor.backupCodesRemaining === 1 ? "" : "s"} remaining.
            </p>

            <div class="flex flex-wrap gap-2">
              <button type="button" class="btn btn-sm" onclick={generate}>
                Generate backup codes
              </button>
              <button type="button" class="btn btn-sm btn-error btn-outline" onclick={disable}>
                Remove authenticator
              </button>
            </div>
          {:else}
            <p class="max-w-prose text-sm opacity-70">
              Password only. A backup code is a way past a second factor, so there is nothing to
              generate until this actor enrols an authenticator.
            </p>
          {/if}
        </Card>
      </div>
    </div>
  </Page>
{/if}
