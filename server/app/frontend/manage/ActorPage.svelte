<script>
  import ScopesEditor from "./ScopesEditor.svelte";

  let { api, uuid, router } = $props();

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

  let actor = $state(null);
  let supported = $state([]);
  let draft = $state({});
  let loading = $state(true);
  let notice = $state(null);
  let failure = $state(null);
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
      failure = thrown.message;
    } finally {
      loading = false;
    }
  }

  load();

  async function act(document, variables, message) {
    notice = null;
    failure = null;

    try {
      await api.query(document, variables);
      notice = message;
      await load();

      return true;
    } catch (thrown) {
      failure = thrown.message;

      return false;
    }
  }

  const saveProfile = () =>
    act(
      `mutation Save($uuid: ID!, ${FIELDS.map(([k]) => `$${k}: String`).join(", ")}) {
        updateActor(uuid: $uuid, ${FIELDS.map(([k]) => `${k}: $${k}`).join(", ")}) { actor { uuid } }
      }`,
      {
        uuid,
        ...Object.fromEntries(
          Object.entries(draft).map(([key, value]) => [key, value === "" ? null : value]),
        ),
      },
      "Saved.",
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
    notice = null;
    failure = null;

    try {
      const data = await api.query(
        `mutation Codes($uuid: ID!) { generateBackupCodes(uuid: $uuid) { codes } }`,
        { uuid },
      );

      codes = data.generateBackupCodes.codes;
      notice = "Backup codes generated. They are shown once and never again.";
      await load();
    } catch (thrown) {
      failure = thrown.message;
    }
  }

  async function recover(document, confirmation) {
    if (!confirm(confirmation)) return;

    notice = null;
    failure = null;
    link = null;

    try {
      const data = await api.query(document, { uuid });
      const result = Object.values(data)[0];

      if (result.delivered) {
        notice = "Emailed. The link is not shown here, so that using it proves the address.";
      } else {
        notice = "No mailer is configured, so pass this link along yourself. It works once.";
        link = result.url;
      }

      await load();
    } catch (thrown) {
      failure = thrown.message;
    }
  }

  const reset = () =>
    recover(
      `mutation Reset($uuid: ID!) { resetPassword(uuid: $uuid) { delivered url } }`,
      "Start a password reset? Every session and refresh token ends when it is used.",
    );

  const resend = () =>
    recover(
      `mutation Resend($uuid: ID!) { resendInvitation(uuid: $uuid) { delivered url } }`,
      "Send a fresh invitation? The previous one stops working.",
    );

  function revokePasskey(id, label) {
    if (!confirm(`Remove the passkey "${label}"?`)) return;

    act(
      `mutation Revoke($uuid: ID!, $id: ID!) { revokePasskey(uuid: $uuid, id: $id) { actor { uuid } } }`,
      { uuid, id },
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

<button class="btn btn-ghost btn-sm mb-4" onclick={() => router.go("/actors")}>← Actors</button>

{#if loading && !actor}
  <div class="py-16 grid place-items-center"><span class="loading loading-spinner"></span></div>
{:else if !actor}
  <div class="alert alert-error text-sm" role="alert">{failure ?? "No actor with that uuid."}</div>
{:else}
  <h1 class="text-xl font-bold mb-1">{actor.nickname}</h1>
  <p class="text-xs opacity-60 font-mono mb-4">{actor.uuid}</p>

  {#if notice}<div class="alert alert-success text-sm mb-4">{notice}</div>{/if}
  {#if failure}<div class="alert alert-error text-sm mb-4" role="alert">{failure}</div>{/if}

  {#if codes}
    <div class="alert alert-warning flex-col items-start gap-2 mb-4">
      <span class="font-medium">Write these down. They are not recoverable.</span>
      <div class="font-mono text-sm grid grid-cols-2 md:grid-cols-5 gap-2">
        {#each codes as code (code)}<span>{code}</span>{/each}
      </div>
    </div>
  {/if}

  <div class="grid md:grid-cols-2 gap-4 items-start">
    <section class="card bg-base-100">
      <div class="card-body gap-3">
        <h2 class="card-title text-base">Profile</h2>
        <p class="text-xs opacity-70">
          Released under the <span class="font-mono">profile</span> and
          <span class="font-mono">email</span> scopes.
        </p>

        {#each FIELDS as [key, label] (key)}
          <label class="form-control">
            <span class="label-text text-xs opacity-70">{label}</span>
            <input class="input input-sm input-bordered w-full" bind:value={draft[key]} />
          </label>
        {/each}

        <button class="btn btn-primary btn-sm" onclick={saveProfile}>Save profile</button>
      </div>
    </section>

    <div class="flex flex-col gap-4">
      <section class="card bg-base-100">
        <div class="card-body gap-3">
          <h2 class="card-title text-base">Scopes</h2>
          <p class="text-xs opacity-70">
            The ceiling on what any client may be granted on this actor's behalf.
          </p>

          <ScopesEditor value={actor.scopes} available={supported} onchange={saveScopes} />
        </div>
      </section>

      <section class="card bg-base-100">
        <div class="card-body gap-3">
          <h2 class="card-title text-base">Access</h2>

          {#if actor.activated}
            <p class="text-sm opacity-70">
              This account has a password. A reset sends a one-time link and signs it out
              everywhere.
            </p>
            <button class="btn btn-sm self-start" onclick={reset}>Reset password</button>
          {:else}
            <p class="text-sm opacity-70">
              Invited{actor.invitedAt ? ` on ${actor.invitedAt.slice(0, 10)}` : ""}, and has not
              accepted yet. There is no password to reset until they do.
            </p>
            <button class="btn btn-sm self-start" onclick={resend}>Resend invitation</button>
          {/if}

          {#if link}
            <p class="font-mono text-xs break-all bg-base-200 rounded px-2 py-1">{link}</p>
          {/if}
        </div>
      </section>

      <section class="card bg-base-100">
        <div class="card-body gap-3">
          <h2 class="card-title text-base">Passkeys</h2>

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
                        class="link text-xs text-error"
                        onclick={() => revokePasskey(passkey.id, passkey.label)}
                      >Remove</button>
                    </span>
                  </div>

                  {#if passkey.compromise}
                    <span class="text-xs text-error">
                      Compromise reported for this model: {passkey.compromise
                        .toLowerCase()
                        .replaceAll("_", " ")}.
                    </span>
                  {/if}

                  <span class="text-xs opacity-60 font-mono">{passkey.aaguid ?? "no aaguid"}</span>
                </li>
              {/each}
            </ul>
          {/if}
        </div>
      </section>

      <section class="card bg-base-100">
        <div class="card-body gap-3">
          <h2 class="card-title text-base">Second factor</h2>

          {#if actor.otpEnabled}
            <p class="text-sm">
              Authenticator enabled. {actor.backupCodesRemaining} backup
              code{actor.backupCodesRemaining === 1 ? "" : "s"} remaining.
            </p>

            <div class="flex gap-2">
              <button class="btn btn-sm" onclick={generate}>Generate backup codes</button>
              <button class="btn btn-sm btn-error btn-outline" onclick={disable}>Remove</button>
            </div>
          {:else}
            <p class="text-sm opacity-70">
              Password only. A backup code is a way past a second factor, so there is nothing to
              generate until this actor enrols an authenticator.
            </p>
          {/if}
        </div>
      </section>
    </div>
  </div>
{/if}
