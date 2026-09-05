<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { moment, since } from "./lib/format.js";
  import Link from "./ui/Link.svelte";
  import Loader from "./ui/Loader.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Switch from "./ui/Switch.svelte";
  import Table from "./ui/Table.svelte";

  let { api } = $props();

  const QUERY = `
    query Devices($blocked: Boolean) {
      devices(blocked: $blocked) {
        id label category ipAddress userAgent known lastSeenAt blockedAt
        actors { uuid nickname }
      }
    }
  `;

  const COLUMNS = ["Device", "Who signs in on it", "Where from", "Last seen", { right: true }];

  const feedback = createFeedback();

  let blocked = $state(false);
  let token = $state(0);

  const stamp = $derived(`${blocked}:${token}`);

  async function act(mutation, device, notice, question = null) {
    if (question && !confirm(question)) return;

    const done = await feedback.attempt(
      () =>
        api.query(`mutation Act($id: ID!) { ${mutation}(id: $id) { device { id } } }`, {
          id: device.id,
        }),
      notice,
    );

    if (done) token += 1;
  }

  const signOut = (device) =>
    act("signOutDevice", device, `Signed ${device.label} out everywhere.`);

  const block = (device) =>
    act(
      "blockDevice",
      device,
      `${device.label} is blocked.`,
      `Block ${device.label}? Nobody will be able to sign in on it until it is unblocked.`,
    );

  const unblock = (device) => act("unblockDevice", device, `${device.label} is unblocked.`);
</script>

<Page
  title="Devices"
  lede="Browsers this server has recognised. Blocking one refuses it before any password is checked."
>
  {#snippet actions()}
    <Switch bind:checked={blocked} label="Blocked only" />
  {/snippet}

  <Notices feedback={feedback.state} />

  {#key stamp}
    <Loader load={() => api.query(QUERY, { blocked })}>
      {#snippet children(data)}
        <Table
          columns={COLUMNS}
          count={data.devices.length}
          empty={blocked ? "No device is blocked." : "No devices have been seen yet."}
        >
          {#snippet rows()}
            {#each data.devices as device (device.id)}
              <tr class="hover">
                <td>
                  <div class="flex flex-wrap items-center gap-2">
                    <span class="font-medium">{device.label}</span>
                    {#if device.blockedAt}
                      <span class="badge badge-error badge-sm">blocked</span>
                    {:else if !device.known}
                      <span class="badge badge-warning badge-xs">unrecognised</span>
                    {/if}
                  </div>
                  <div class="text-xs opacity-50">{device.category}</div>
                </td>
                <td class="text-xs">
                  {#if device.actors.length}
                    <div class="flex flex-wrap gap-x-2">
                      {#each device.actors as actor (actor.uuid)}
                        <Link to={`/actors/${actor.uuid}`} class="link link-hover">
                          {actor.nickname}
                        </Link>
                      {/each}
                    </div>
                  {:else}
                    —
                  {/if}
                </td>
                <td class="text-xs">
                  <div class="font-mono">{device.ipAddress ?? "—"}</div>
                  <div class="max-w-md truncate opacity-50">{device.userAgent ?? ""}</div>
                </td>
                <td class="text-xs opacity-70" title={moment(device.lastSeenAt)}>
                  {since(device.lastSeenAt)}
                </td>
                <td>
                  <div class="flex justify-end gap-2 whitespace-nowrap">
                    <button
                      type="button"
                      class="btn btn-xs btn-outline"
                      onclick={() => signOut(device)}
                    >
                      Sign out
                    </button>

                    {#if device.blockedAt}
                      <button type="button" class="btn btn-xs" onclick={() => unblock(device)}>
                        Unblock
                      </button>
                    {:else}
                      <button
                        type="button"
                        class="btn btn-xs btn-error btn-outline"
                        onclick={() => block(device)}
                      >
                        Block
                      </button>
                    {/if}
                  </div>
                </td>
              </tr>
            {/each}
          {/snippet}
        </Table>
      {/snippet}
    </Loader>
  {/key}
</Page>
