<script>
  import { day, moment, since } from "./lib/format.js";

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
      "Session revoked.",
      "Revoke this session? That browser is signed out at once.",
    );

  const onDevice = (mutation, device, notice, question = null) =>
    act(
      `mutation Act($id: ID!) { ${mutation}(id: $id) { device { id } } }`,
      { id: device.id },
      notice,
      question,
    );

  const signOutDevice = (device) =>
    onDevice("signOutDevice", device, `Signed ${device.label} out everywhere.`);

  const block = (device) =>
    onDevice(
      "blockDevice",
      device,
      `${device.label} is blocked.`,
      `Block ${device.label}? Nobody will be able to sign in on it until it is unblocked.`,
    );

  const unblock = (device) => onDevice("unblockDevice", device, `${device.label} is unblocked.`);

  const signOutEverywhere = () =>
    act(
      `mutation SignOut($uuid: ID!) { signOutActor(uuid: $uuid) { actor { uuid } } }`,
      { uuid: actor.uuid },
      "Signed out everywhere.",
      `Sign ${actor.nickname} out everywhere? Every session and refresh token ends, and no device counts as a second factor any more.`,
    );
</script>

<div class="flex flex-col gap-5">
  <div class="grid items-start gap-5 {columns ? 'lg:grid-cols-2' : ''}">
    <section class="flex min-w-0 flex-col gap-2.5">
      <h3 class="legend">Sessions</h3>

      {#if actor.sessions.length === 0}
        <p class="text-sm opacity-55">Not signed in anywhere right now.</p>
      {:else}
        <ul class="flex flex-col gap-1.5">
          {#each actor.sessions as session (session.id)}
            <li class="slat">
              <div class="flex items-baseline justify-between gap-3">
                <span class="font-mono text-sm">{session.ipAddress ?? "—"}</span>
                <button type="button" class="link text-xs text-error" onclick={() => revoke(session)}>
                  Revoke
                </button>
              </div>

              <span class="truncate text-xs opacity-45">{session.userAgent ?? ""}</span>

              <div class="flex flex-wrap gap-x-4 text-xs opacity-60">
                <span title={moment(session.authenticatedAt)}>
                  Signed in {since(session.authenticatedAt)}
                </span>
                <span>Expires {day(session.expiresAt)}</span>
              </div>
            </li>
          {/each}
        </ul>
      {/if}
    </section>

    <section class="flex min-w-0 flex-col gap-2.5">
      <h3 class="legend">Devices</h3>

      {#if actor.devices.length === 0}
        <p class="text-sm opacity-55">Nothing has signed in on their behalf yet.</p>
      {:else}
        <ul class="flex flex-col gap-1.5">
          {#each actor.devices as device (device.id)}
            <li class="slat">
              <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                <span class="flex flex-wrap items-baseline gap-2">
                  <span class="text-sm font-medium">{device.label}</span>
                  {#if device.blockedAt}
                    <span class="badge badge-error badge-xs">blocked</span>
                  {:else if !device.known}
                    <span class="badge badge-warning badge-xs">unrecognised</span>
                  {/if}
                </span>

                <span class="flex items-baseline gap-3">
                  <button
                    type="button"
                    class="link text-xs"
                    onclick={() => signOutDevice(device)}
                  >
                    Sign out
                  </button>

                  {#if device.blockedAt}
                    <button type="button" class="link text-xs" onclick={() => unblock(device)}>
                      Unblock
                    </button>
                  {:else}
                    <button
                      type="button"
                      class="link text-xs text-error"
                      onclick={() => block(device)}
                    >
                      Block
                    </button>
                  {/if}
                </span>
              </div>

              <span class="truncate text-xs opacity-45">{device.userAgent ?? device.category}</span>

              <div class="flex flex-wrap gap-x-4 text-xs opacity-60">
                <span class="font-mono">{device.ipAddress ?? "—"}</span>
                <span title={moment(device.lastSeenAt)}>Last seen {since(device.lastSeenAt)}</span>
              </div>
            </li>
          {/each}
        </ul>
      {/if}
    </section>
  </div>

  <button type="button" class="btn btn-sm btn-error btn-outline self-start" onclick={signOutEverywhere}>
    Sign out everywhere
  </button>
</div>
