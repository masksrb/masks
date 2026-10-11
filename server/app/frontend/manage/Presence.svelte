<script>
  import { t } from "./lib/copy.js";
  import { day, moment, since } from "./lib/format.js";
  import Link from "./ui/Link.svelte";

  let { api, feedback, actor, onchange, columns = false } = $props();

  async function act(document, variables, notice, question = null) {
    if (question && !confirm(question)) return;

    const done = await feedback.attempt(() => api.query(document, variables), notice);

    if (done) await onchange();
  }

  const revoke = (session) =>
    act(
      `mutation Revoke($id: ID!) { revokeSession(id: $id) { session { revokedAt } } }`,
      { id: session.id },
      t("presence.session_revoked"),
      t("presence.revoke_question"),
    );

  const onDevice = (mutation, device, notice, question = null) =>
    act(
      `mutation Act($id: ID!) { ${mutation}(id: $id) { device { id } } }`,
      { id: device.id },
      notice,
      question,
    );

  const signOutDevice = (device) =>
    onDevice("signOutDevice", device, t("presence.device_signed_out", { label: device.label }));

  const block = (device) =>
    onDevice(
      "blockDevice",
      device,
      t("presence.device_blocked", { label: device.label }),
      t("presence.block_question", { label: device.label }),
    );

  const unblock = (device) => onDevice("unblockDevice", device, t("presence.device_unblocked", { label: device.label }));

  const signOutEverywhere = () =>
    act(
      `mutation SignOut($uuid: ID!) { signOutActor(uuid: $uuid) { actor { uuid } } }`,
      { uuid: actor.uuid },
      t("presence.signed_out_everywhere"),
      t("presence.sign_out_everywhere_question", { identifier: actor.identifier }),
    );
  const LIMIT = 4;

  let allSessions = $state(false);
  let allDevices = $state(false);

  const sessions = $derived(allSessions ? actor.sessions : actor.sessions.slice(0, LIMIT));
  const devices = $derived(allDevices ? actor.devices : actor.devices.slice(0, LIMIT));
</script>

<div class="flex flex-col gap-5">
  <div class="grid items-start gap-5 {columns ? 'lg:grid-cols-2' : ''}">
    <section class="flex min-w-0 flex-col gap-2.5">
      <h3 class="legend">{t("presence.sessions")}</h3>

      {#if actor.sessions.length === 0}
        <p class="text-sm opacity-75">{t("presence.no_sessions")}</p>
      {:else}
        <ul class="slats">
          {#each sessions as session (session.id)}
            <li class="slat">
              <div class="flex items-baseline justify-between gap-3">
                <span class="font-mono text-sm">{session.ipAddress ?? "—"}</span>
                <button type="button" class="link text-xs text-error" onclick={() => revoke(session)}>
                  {t("presence.revoke")}
                </button>
              </div>

              <span class="truncate text-xs opacity-75">{session.userAgent ?? ""}</span>

              <div class="flex flex-wrap gap-x-4 text-xs opacity-80">
                <span title={moment(session.authenticatedAt)}>
                  {t("presence.signed_in", { when: since(session.authenticatedAt) })}
                </span>
                <span>{t("presence.expires", { when: day(session.expiresAt) })}</span>
              </div>
            </li>
          {/each}
        </ul>

        {#if !allSessions && actor.sessions.length > LIMIT}
          <button type="button" class="btn btn-ghost btn-sm self-start" onclick={() => (allSessions = true)}>
            {t("presence.show_more", { count: actor.sessions.length - LIMIT })}
          </button>
        {/if}
      {/if}
    </section>

    <section class="flex min-w-0 flex-col gap-2.5">
      <h3 class="legend">{t("presence.devices")}</h3>

      {#if actor.devices.length === 0}
        <p class="text-sm opacity-75">{t("presence.no_devices")}</p>
      {:else}
        <ul class="slats">
          {#each devices as device (device.id)}
            <li class="slat">
              <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                <span class="flex flex-wrap items-baseline gap-2">
                  <Link to={`/actors/devices/${device.id}`} class="link link-hover text-sm font-medium">
                    {device.label}
                  </Link>
                  {#if device.blockedAt}
                    <span class="badge badge-error badge-xs">{t("presence.blocked")}</span>
                  {:else if !device.known}
                    <span class="badge badge-warning badge-xs">{t("presence.unrecognised")}</span>
                  {/if}
                </span>

                <span class="flex items-baseline gap-3">
                  <button
                    type="button"
                    class="link text-xs"
                    onclick={() => signOutDevice(device)}
                  >
                    {t("presence.sign_out")}
                  </button>

                  {#if device.blockedAt}
                    <button type="button" class="link text-xs" onclick={() => unblock(device)}>
                      {t("presence.unblock")}
                    </button>
                  {:else}
                    <button
                      type="button"
                      class="link text-xs text-error"
                      onclick={() => block(device)}
                    >
                      {t("presence.block")}
                    </button>
                  {/if}
                </span>
              </div>

              <span class="truncate text-xs opacity-75">{device.userAgent ?? device.category}</span>

              <div class="flex flex-wrap gap-x-4 text-xs opacity-80">
                <span class="font-mono">{device.ipAddress ?? "—"}</span>
                <span title={moment(device.lastSeenAt)}>{t("presence.last_seen", { when: since(device.lastSeenAt) })}</span>
              </div>
            </li>
          {/each}
        </ul>

        {#if !allDevices && actor.devices.length > LIMIT}
          <button type="button" class="btn btn-ghost btn-sm self-start" onclick={() => (allDevices = true)}>
            {t("presence.show_more", { count: actor.devices.length - LIMIT })}
          </button>
        {/if}
      {/if}
    </section>
  </div>

  <button type="button" class="btn btn-sm btn-error btn-outline self-start" onclick={signOutEverywhere}>
    {t("presence.sign_out_everywhere")}
  </button>
</div>
