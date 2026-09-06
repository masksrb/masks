<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, since } from "./lib/format.js";
  import { useRouter } from "./lib/router.svelte.js";
  import Events from "./Events.svelte";
  import Presence from "./Presence.svelte";
  import ScopesEditor from "./ScopesEditor.svelte";
  import Card from "./ui/Card.svelte";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api, uuid } = $props();

  const router = useRouter();

  const FIELDS = [
    ["nickname", "Username"],
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
        photoUploaded avatars { photo identicon initials }
        sessions { id ipAddress userAgent authenticatedAt expiresAt }
        devices { id label category known ipAddress userAgent lastSeenAt blockedAt }
        events(limit: 25) {
          id action createdAt ipAddress details
          by { uuid nickname }
          client { clientId name }
          device { id label }
        }
      }
      viewer { uuid }
      scopesSupported
    }
  `;

  const feedback = createFeedback();

  let actor = $state(null);
  let viewer = $state(null);
  let supported = $state([]);
  let draft = $state({});
  let loading = $state(true);
  let codes = $state(null);
  let link = $state(null);
  let uploading = $state(false);

  const yourself = $derived(Boolean(actor && viewer && actor.uuid === viewer.uuid));

  async function load() {
    loading = true;

    try {
      const data = await api.query(QUERY, { uuid });

      actor = data.actor;
      viewer = data.viewer;
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

  const confirmEmail = () =>
    recover(
      `mutation Verify($uuid: ID!) { verifyEmail(uuid: $uuid) { delivered url } }`,
      "Send a confirmation link for this address? Any earlier one stops working.",
    );

  function revokePasskey(passkey) {
    if (!confirm(`Remove the passkey “${passkey.label}”?`)) return;

    act(
      `mutation Revoke($uuid: ID!, $id: ID!) { revokePasskey(uuid: $uuid, id: $id) { actor { uuid } } }`,
      { uuid, id: passkey.id },
      "Passkey removed.",
    );
  }

  async function choose(event) {
    const input = event.currentTarget;
    const file = input.files?.[0];

    if (!file) return;

    uploading = true;

    await act(
      `mutation Upload($uuid: ID!, $photo: Upload!) {
        uploadAvatar(uuid: $uuid, photo: $photo) { actor { uuid } }
      }`,
      { uuid, photo: file },
      "Photo updated.",
    );

    uploading = false;
    input.value = "";
  }

  function removePhoto() {
    if (!confirm("Remove this actor's uploaded photo?")) return;

    act(
      `mutation Remove($uuid: ID!) { removeAvatar(uuid: $uuid) { actor { uuid } } }`,
      { uuid },
      "Photo removed.",
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

  async function remove() {
    const question =
      `Delete ${actor.nickname}? Their sessions, tokens, passkeys, consents and avatar go with them. ` +
      "There is no undo, and nothing is kept.";

    if (!confirm(question)) return;

    const data = await feedback.attempt(() =>
      api.query(`mutation Delete($uuid: ID!) { deleteActor(uuid: $uuid) { nickname } }`, { uuid }),
    );

    if (data) router.go("/people");
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
    back={{ to: "/people", label: "People" }}
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
      <div class="flex flex-col gap-4">
        <Card title="Profile" lede="Released under the profile and email scopes.">
          <div class="grid gap-3 sm:grid-cols-2">
            {#each FIELDS as [key, label] (key)}
              <Field {label} bind:value={draft[key]} />
            {/each}
          </div>

          <button type="button" class="btn btn-primary btn-sm self-start" onclick={saveProfile}>
            Save profile
          </button>
        </Card>

        <Card
          title="Where they are"
          lede={yourself ? "Signing out everywhere takes this console with it." : null}
        >
          <Presence {api} {feedback} {actor} onchange={load} />
        </Card>
      </div>

      <div class="flex flex-col gap-4">
        <Card title="Avatar" lede="Only the photo is stored; the rest are drawn.">
          <div class="flex flex-wrap gap-5">
            {#each ["photo", "identicon", "initials"] as style (style)}
              <div class="flex flex-col items-start gap-2">
                {#if actor.avatars[style]}
                  <img
                    src={`${actor.avatars[style]}?size=64`}
                    width="64"
                    height="64"
                    alt=""
                    class="size-16 rounded object-cover"
                    class:drawn={style !== "photo"}
                  />
                {:else}
                  <div class="size-16 rounded border border-dashed border-base-300"></div>
                {/if}
                <span class="text-xs opacity-60">{style}</span>
              </div>
            {/each}
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <input
              type="file"
              class="file-input file-input-sm max-w-full"
              accept="image/png,image/jpeg,image/gif,image/webp"
              aria-label="Upload a photo"
              disabled={uploading}
              onchange={choose}
            />

            {#if actor.photoUploaded}
              <button type="button" class="btn btn-ghost btn-sm" onclick={removePhoto}>
                Remove photo
              </button>
            {/if}
          </div>

          {#if uploading}
            <span class="text-xs opacity-60">Storing...</span>
          {/if}
        </Card>

        <Card title="Scopes" lede="The ceiling for any client acting on their behalf.">
          <ScopesEditor value={actor.scopes} available={supported} onchange={saveScopes} />
        </Card>

        <Card title="Access">
          {#if actor.activated}
            <button type="button" class="btn btn-sm self-start" onclick={reset}>
              Reset password
            </button>
          {:else}
            <p class="text-sm opacity-70">
              Invited{actor.invitedAt ? ` ${day(actor.invitedAt)}` : ""}, not accepted.
            </p>
            <button type="button" class="btn btn-sm self-start" onclick={resend}>
              Resend invitation
            </button>
          {/if}

          {#if actor.email && !actor.emailVerified}
            <p class="text-sm opacity-70">{actor.email} is unconfirmed.</p>
            <button type="button" class="btn btn-sm self-start" onclick={confirmEmail}>
              Send a confirmation link
            </button>
          {/if}
        </Card>

        <Card title="Passkeys" lede="Each one counts as both factors on its own.">
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
                        <span class="badge badge-success badge-xs">verifying</span>
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
            <p class="text-sm opacity-70">Password only — nothing enrolled.</p>
          {/if}
        </Card>

        <Card title="Activity" lede="What has happened to this account, newest first.">
          <Events events={actor.events} showActor={false} empty="Nothing recorded yet." />
        </Card>

        <Card title="Delete">
          {#if yourself}
            <p class="text-sm opacity-70">This is you — another administrator has to do it.</p>
          {:else}
            <button
              type="button"
              class="btn btn-sm btn-error btn-outline self-start"
              onclick={remove}
            >
              Delete {actor.nickname}
            </button>
          {/if}
        </Card>
      </div>
    </div>
  </Page>
{/if}
