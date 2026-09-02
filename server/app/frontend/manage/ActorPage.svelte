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
        backupCodesGeneratedAt lastLoginAt createdAt
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
