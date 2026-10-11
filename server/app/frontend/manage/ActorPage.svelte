<script>
  import { t } from "./lib/copy.js";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, since } from "./lib/format.js";
  import { useRouter } from "./lib/router.svelte.js";
  import Connections from "./Connections.svelte";
  import Consents from "./Consents.svelte";
  import Events from "./Events.svelte";
  import Presence from "./Presence.svelte";
  import Tokens from "./Tokens.svelte";
  import ScopesEditor from "./ScopesEditor.svelte";
  import Section from "./ui/Section.svelte";
  import Field from "./ui/Field.svelte";
  import Link from "./ui/Link.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Spinner from "./ui/Spinner.svelte";

  let { api, uuid } = $props();

  const router = useRouter();

  const FIELDS = [
    ["nickname", t("actor.fields.nickname")],
    ["name", t("actor.fields.name")],
    ["email", t("actor.fields.email")],
  ];

  const MORE = [
    ["givenName", t("actor.fields.given_name")],
    ["familyName", t("actor.fields.family_name")],
    ["middleName", t("actor.fields.middle_name")],
    ["profileUrl", t("actor.fields.profile_url")],
    ["pictureUrl", t("actor.fields.picture_url")],
    ["websiteUrl", t("actor.fields.website_url")],
    ["gender", t("actor.fields.gender")],
    ["birthdate", t("actor.fields.birthdate")],
    ["zoneinfo", t("actor.fields.zoneinfo")],
    ["locale", t("actor.fields.locale")],
  ];

  const PROFILE = [...FIELDS, ...MORE];

  const QUERY = `
    query Actor($uuid: ID!) {
      actor(uuid: $uuid) {
        uuid identifier nickname email emailVerified phone phoneVerified signedUpAt pendingApproval
        recoveryRequestedAt
        groups { key }
        groupLabels
        suspendedAt externalId
        memberships { externalId organization { key name } }
        scopes otpEnabled emailCodesEnabled textCodesEnabled backupCodesRemaining
        backupCodesGeneratedAt lastLoginAt createdAt activated invitedAt
        passkeys { id label aaguid certification compromise userVerified lastUsedAt }
        name givenName familyName middleName profileUrl pictureUrl websiteUrl
        gender birthdate zoneinfo locale
        photoUploaded avatars { photo identicon initials }
        sessions { id ipAddress userAgent authenticatedAt expiresAt }
        devices { id label category known ipAddress userAgent lastSeenAt blockedAt }
        connections {
          id subject label email emailVerified connectedAt signedInAt delegable
          provider { key name }
          delegations { id releasedAt client { clientId name } }
        }
        consents {
          id scopes audience updatedAt expiresAt authorizationDetails
          client { clientId name }
        }
        tokens {
          id kind scopes audience parentId createdAt expiresAt
          client { clientId name }
          device { id label }
        }
        events(limit: 25) {
          id action label createdAt ipAddress details
          by { uuid identifier }
          client { clientId name }
          device { id label }
        }
      }
      groups { key name }
      viewer { uuid }
      scopesSupported
    }
  `;

  const feedback = createFeedback();

  let actor = $state(null);
  let viewer = $state(null);
  let groups = $state([]);
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
      groups = data.groups;
      supported = data.scopesSupported;
      draft = Object.fromEntries(PROFILE.map(([key]) => [key, data.actor?.[key] ?? ""]));
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

  const belongs = (group) => actor.groups.some((held) => held.key === group.key);

  const toggleGroup = (group) =>
    act(
      belongs(group)
        ? `mutation Leave($key: String!, $uuid: ID!) { removeGroupMember(key: $key, uuid: $uuid) { group { key } } }`
        : `mutation Join($key: String!, $uuid: ID!) { addGroupMember(key: $key, uuid: $uuid) { group { key } } }`,
      { key: group.key, uuid },
      belongs(group)
        ? t("actor.left_group", { group: group.name })
        : t("actor.joined_group", { group: group.name }),
    );

  const saveProfile = () =>
    act(
      `mutation Save($uuid: ID!, ${PROFILE.map(([key]) => `$${key}: String`).join(", ")}) {
        updateActor(uuid: $uuid, ${PROFILE.map(([key]) => `${key}: $${key}`).join(", ")}) { actor { uuid } }
      }`,
      {
        uuid,
        ...Object.fromEntries(
          Object.entries(draft).map(([key, value]) => [key, value === "" ? null : value]),
        ),
      },
      t("actor.profile_saved"),
    );

  const saveScopes = (scopes) =>
    act(
      `mutation Scopes($uuid: ID!, $scopes: [String!]!) {
        setActorScopes(uuid: $uuid, scopes: $scopes) { actor { scopes } }
      }`,
      { uuid, scopes },
      t("actor.scopes_updated"),
    );

  async function generate() {
    codes = null;

    const data = await act(
      `mutation Codes($uuid: ID!) { generateBackupCodes(uuid: $uuid) { codes } }`,
      { uuid },
      t("actor.codes_generated"),
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
      feedback.say(t("actor.emailed"));
    } else {
      feedback.say(t("actor.no_mailer"));
      link = result.url;
    }
  }

  const reset = () =>
    recover(
      `mutation Reset($uuid: ID!) { resetPassword(uuid: $uuid) { delivered url } }`,
      t("actor.reset_question"),
    );

  const resend = () =>
    recover(
      `mutation Resend($uuid: ID!) { resendInvitation(uuid: $uuid) { delivered url } }`,
      t("actor.resend_question"),
    );

  const confirmEmail = () =>
    recover(
      `mutation Verify($uuid: ID!) { verifyEmail(uuid: $uuid) { delivered url } }`,
      t("actor.confirm_question"),
    );

  function revokePasskey(passkey) {
    if (!confirm(t("actor.remove_passkey_question", { label: passkey.label }))) return;

    act(
      `mutation Revoke($uuid: ID!, $id: ID!) { revokePasskey(uuid: $uuid, id: $id) { actor { uuid } } }`,
      { uuid, id: passkey.id },
      t("actor.passkey_removed"),
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
      t("actor.photo_updated"),
    );

    uploading = false;
    input.value = "";
  }

  function removePhoto() {
    if (!confirm(t("actor.remove_photo_question"))) return;

    act(
      `mutation Remove($uuid: ID!) { removeAvatar(uuid: $uuid) { actor { uuid } } }`,
      { uuid },
      t("actor.photo_removed"),
    );
  }

  function disable() {
    if (!confirm(t("actor.disable_question"))) return;

    act(
      `mutation Disable($uuid: ID!) { disableAuthenticator(uuid: $uuid) { actor { otpEnabled } } }`,
      { uuid },
      t("actor.authenticator_removed"),
    );
  }

  const CODE_FACTORS = [
    ["email", "emailCodesEnabled", t("actor.factors.email.name"), t("actor.factors.email.lower")],
    ["sms", "textCodesEnabled", t("actor.factors.sms.name"), t("actor.factors.sms.lower")],
  ];

  function turnOff(factor, name, lower) {
    if (!confirm(t("actor.turn_off_question", { name: lower }))) return;

    act(
      `mutation TurnOff($uuid: ID!, $factor: String!) {
        disableCodeFactor(uuid: $uuid, factor: $factor) { actor { uuid } }
      }`,
      { uuid, factor },
      t("actor.turned_off", { name }),
    );
  }

  function suspend() {
    if (!confirm(t("actor.suspend_question", { identifier: actor.identifier }))) return;

    act(
      `mutation Suspend($uuid: ID!) { suspendActor(uuid: $uuid) { actor { suspendedAt } } }`,
      { uuid },
      t("actor.suspended"),
    );
  }

  function restore() {
    act(
      `mutation Restore($uuid: ID!) { restoreActor(uuid: $uuid) { actor { suspendedAt } } }`,
      { uuid },
      t("actor.restored"),
    );
  }

  async function remove() {
    if (!confirm(t("actor.delete_question", { identifier: actor.identifier }))) return;

    const data = await feedback.attempt(() =>
      api.query(`mutation Delete($uuid: ID!) { deleteActor(uuid: $uuid) { identifier } }`, { uuid }),
    );

    if (data) router.go("/actors");
  }
</script>

{#if loading && !actor}
  <Spinner />
{:else if !actor}
  <div class="alert alert-error alert-soft text-sm" role="alert">
    {feedback.state.failure ?? t("actor.missing")}
  </div>
{:else}
  <Page
    title={actor.identifier}
    id={actor.uuid}
    back={{ to: "/actors", label: t("actor.back") }}
    lede={actor.activated
      ? t("actor.signed_in_lede", { when: since(actor.lastLoginAt, t("actor.never")) })
      : t("actor.invited_lede")}
  >
    <Notices feedback={feedback.state} />

    {#if link}
      <div class="alert alert-info alert-soft flex-col items-start gap-2" role="status">
        <span class="font-medium">{t("actor.link_once")}</span>
        <code class="font-mono text-xs break-all">{link}</code>
      </div>
    {/if}

    {#if codes}
      <div class="alert alert-warning alert-soft flex-col items-start gap-2" role="status">
        <span class="font-medium">{t("actor.write_down")}</span>
        <div class="grid grid-cols-2 gap-2 font-mono text-sm md:grid-cols-5">
          {#each codes as code (code)}<span>{code}</span>{/each}
        </div>
      </div>
    {/if}

    <div class="grid items-start gap-4 md:grid-cols-2">
      <div class="flex flex-col gap-4">
        <Section title={t("actor.profile")}>
          <div class="grid gap-3 sm:grid-cols-3">
            {#each FIELDS as [key, label] (key)}
              <Field {label} bind:value={draft[key]} />
            {/each}
          </div>

          <details class="more" open={MORE.some(([key]) => draft[key])}>
            <summary>{t("actor.more_fields")}</summary>
            <div class="grid gap-3 pt-3 sm:grid-cols-2">
              {#each MORE as [key, label] (key)}
                <Field {label} bind:value={draft[key]} />
              {/each}
            </div>
          </details>

          <button type="button" class="btn btn-primary btn-sm self-start" onclick={saveProfile}>
            {t("actor.save_profile")}
          </button>
        </Section>

        <Section
          title={t("actor.signed_in")}
          lede={yourself ? t("actor.signed_in_yourself") : null}
        >
          <Presence {api} {feedback} {actor} onchange={load} />
        </Section>

        <Section title={t("actor.consents")}>
          <Consents {api} {feedback} rows={actor.consents} onchange={load} />
        </Section>

        <Section title={t("actor.connections")}>
          <Connections {api} {feedback} rows={actor.connections} onchange={load} />
        </Section>

        <Section
          title={t("actor.tokens")}
        >
          <Tokens {api} {feedback} rows={actor.tokens} onchange={load} />
        </Section>
      </div>

      <div class="flex flex-col gap-4">
        <Section title={t("actor.photo")}>
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
                <span class="hint">{t(`actor.styles.${style}`)}</span>
              </div>
            {/each}
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <label class="btn btn-sm" class:btn-disabled={uploading}>
              {t("actor.upload_photo")}
              <input
                type="file"
                class="sr-only"
                accept="image/png,image/jpeg,image/gif,image/webp"
                disabled={uploading}
                onchange={choose}
              />
            </label>

            {#if actor.photoUploaded}
              <button type="button" class="btn btn-ghost btn-sm" onclick={removePhoto}>
                {t("actor.remove_photo")}
              </button>
            {/if}
          </div>

          {#if uploading}
            <span class="hint">{t("actor.uploading")}</span>
          {/if}
        </Section>

        <Section title={t("actor.scopes")}>
          <ScopesEditor value={actor.scopes} available={supported} onchange={saveScopes} />
        </Section>

        <Section title={t("actor.access")}>
          {#if actor.suspendedAt}
            <div class="alert alert-warning alert-soft flex-wrap items-center gap-3 text-sm" role="status">
              <span>{t("actor.suspended_on", { day: day(actor.suspendedAt) })}</span>
              <button type="button" class="btn btn-sm" onclick={restore}>{t("actor.restore")}</button>
            </div>
          {/if}

          {#if actor.externalId}
            <p class="hint">
              {t("actor.provisioned_as")} <span class="font-mono">{actor.externalId}</span>.
              {t("actor.provider_may_change")}
            </p>
          {/if}
          {#each actor.memberships.filter((membership) => membership.externalId) as membership (membership.organization.key)}
            <p class="hint">
              {t("actor.directory_provisioned", { organization: membership.organization.name })}
              <span class="font-mono">{membership.externalId}</span>, {t("actor.directory_may_change")}
            </p>
          {/each}
          {#if actor.activated}
            <button type="button" class="btn btn-sm self-start" onclick={reset}>
              {t("actor.reset_password")}
            </button>
          {:else}
            <p class="text-sm opacity-85">
              {actor.invitedAt
                ? t("actor.invited_on", { day: day(actor.invitedAt) })
                : t("actor.invited")}
            </p>
            <button type="button" class="btn btn-sm self-start" onclick={resend}>
              {t("actor.resend")}
            </button>
          {/if}

          {#if actor.email && !actor.emailVerified}
            <p class="text-sm opacity-85">{t("actor.unconfirmed", { email: actor.email })}</p>
            <button type="button" class="btn btn-sm self-start" onclick={confirmEmail}>
              {t("actor.send_confirmation")}
            </button>
          {/if}
        </Section>

        <Section title={t("actor.passkeys")}>
          {#if actor.passkeys.length === 0}
            <p class="text-sm opacity-85">{t("actor.no_passkeys")}</p>
          {:else}
            <ul class="flex flex-col gap-2">
              {#each actor.passkeys as passkey (passkey.id)}
                <li class="flex flex-col gap-1 tray px-3 py-2">
                  <div class="flex items-baseline justify-between gap-3">
                    <span class="text-sm font-medium">{passkey.label}</span>
                    <span class="flex items-baseline gap-2">
                      {#if passkey.userVerified}
                        <span class="badge badge-success badge-xs">{t("actor.verifying")}</span>
                      {/if}
                      {#if passkey.certification}
                        <span class="badge badge-ghost badge-xs">{passkey.certification}</span>
                      {/if}
                      <button
                        type="button"
                        class="link text-xs text-error"
                        onclick={() => revokePasskey(passkey)}
                      >
                        {t("actor.remove")}
                      </button>
                    </span>
                  </div>

                  {#if passkey.compromise}
                    <span class="text-xs text-error">
                      {t("actor.compromise", {
                        compromise: passkey.compromise.toLowerCase().replaceAll("_", " "),
                      })}
                    </span>
                  {/if}

                  <div class="flex flex-wrap gap-x-4 text-xs opacity-80">
                    <span class="font-mono">{passkey.aaguid ?? t("actor.no_aaguid")}</span>
                    <span>{t("actor.last_used", { when: since(passkey.lastUsedAt, t("actor.never")) })}</span>
                  </div>
                </li>
              {/each}
            </ul>
          {/if}
        </Section>

        {#if actor.pendingApproval}
          <Section
            title={t("actor.approval.title")}
            lede={t("actor.approval.lede")}
          >
            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                class="btn btn-primary btn-sm"
                onclick={() =>
                  act(
                    `mutation Approve($uuid: ID!) { approveActor(uuid: $uuid) { actor { uuid } } }`,
                    { uuid },
                    t("actor.approval.approved"),
                  )}
              >
                {t("actor.approval.approve")}
              </button>
            </div>
          </Section>
        {/if}

        {#if actor.recoveryRequestedAt}
          <Section
            title={t("actor.recovery.title")}
            lede={t("actor.recovery.lede", { when: since(actor.recoveryRequestedAt) })}
          >
            <p class="text-sm opacity-85">
              {t("actor.recovery.explain")}
            </p>

            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                class="btn btn-primary btn-sm"
                onclick={() =>
                  confirm(t("actor.recovery.question", { identifier: actor.identifier })) &&
                  act(
                    `mutation Reset($uuid: ID!) { resetSecondFactors(uuid: $uuid) { actor { uuid } } }`,
                    { uuid },
                    t("actor.recovery.done"),
                  )}
              >
                {t("actor.recovery.reset")}
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                onclick={() =>
                  act(
                    `mutation Dismiss($uuid: ID!) { dismissRecovery(uuid: $uuid) { actor { uuid } } }`,
                    { uuid },
                    t("actor.recovery.dismissed"),
                  )}
              >
                {t("actor.recovery.dismiss")}
              </button>
            </div>
          </Section>
        {/if}

        <Section title={t("actor.groups")}>
          {#if groups.length}
            <div class="flex flex-col gap-1">
              {#each groups as group (group.key)}
                <label class="flex items-center gap-2 text-sm">
                  <input type="checkbox" class="checkbox checkbox-sm" checked={belongs(group)} onchange={() => toggleGroup(group)} />
                  {group.name} <code class="hint font-mono">{group.key}</code>
                </label>
              {/each}
            </div>
          {:else}
            <p class="text-sm opacity-85">{t("actor.no_groups")} <Link to="/settings">{t("actor.add_group")}</Link>.</p>
          {/if}

          {#if actor.groupLabels.length}
            <p class="hint">{t("actor.group_labels", { labels: actor.groupLabels.join(", ") })}</p>
          {/if}
        </Section>

        <Section title={t("actor.second_factor")}>
          {#if actor.otpEnabled}
            <p class="text-sm">
              {t("actor.authenticator_enabled", { count: actor.backupCodesRemaining })}
            </p>

            <div class="flex flex-wrap gap-2">
              <button type="button" class="btn btn-sm" onclick={generate}>
                {t("actor.generate")}
              </button>
              <button type="button" class="btn btn-sm btn-error btn-outline" onclick={disable}>
                {t("actor.remove_authenticator")}
              </button>
            </div>
          {:else if !actor.emailCodesEnabled && !actor.textCodesEnabled}
            <p class="text-sm opacity-85">{t("actor.password_only")}</p>
          {/if}

          {#each CODE_FACTORS.filter(([, field]) => actor[field]) as [factor, , name, lower] (factor)}
            <div class="flex flex-wrap items-center gap-2">
              <span class="text-sm">{t("actor.factor_on", { name })}</span>
              <button
                type="button"
                class="btn btn-sm btn-error btn-outline"
                onclick={() => turnOff(factor, name, lower)}
              >
                {t("actor.turn_off", { name: lower })}
              </button>
            </div>
          {/each}
        </Section>

        <Section title={t("actor.activity")}>
          {#snippet actions()}
            <Link to={`/activity?actor=${actor.uuid}`} class="btn btn-ghost btn-sm">{t("actor.all_activity")}</Link>
          {/snippet}

          <Events events={actor.events} showActor={false} empty={t("actor.no_activity")} />
        </Section>

        <Section title={t("actor.danger")}>
          {#if yourself}
            <p class="text-sm opacity-85">{t("actor.yourself")}</p>
          {:else}
            {#if !actor.suspendedAt}
              <button type="button" class="btn btn-sm btn-warning btn-outline self-start" onclick={suspend}>
                {t("actor.suspend", { identifier: actor.identifier })}
              </button>
            {/if}
            <button
              type="button"
              class="btn btn-sm btn-error btn-outline self-start"
              onclick={remove}
            >
              {t("actor.delete", { identifier: actor.identifier })}
            </button>
          {/if}
        </Section>
      </div>
    </div>
  </Page>
{/if}
