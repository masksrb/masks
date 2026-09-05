<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, moment, since } from "./lib/format.js";
  import Link from "./ui/Link.svelte";
  import Loader from "./ui/Loader.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Table from "./ui/Table.svelte";

  let { api } = $props();

  const QUERY = `
    query Sessions {
      sessions {
        id userAgent ipAddress authenticatedAt expiresAt createdAt
        actor { uuid nickname }
      }
    }
  `;

  const COLUMNS = ["Actor", "Where from", "Signed in", "Expires", { right: true }];

  const feedback = createFeedback();

  let token = $state(0);

  async function revoke(session) {
    const question = `Revoke ${session.actor.nickname}'s session? That browser is signed out at once.`;

    if (!confirm(question)) return;

    const done = await feedback.attempt(
      () =>
        api.query(`mutation Revoke($id: ID!) { revokeSession(id: $id) { session { revokedAt } } }`, {
          id: session.id,
        }),
      "Session revoked.",
    );

    if (done) token += 1;
  }
</script>

<Page
  title="Sessions"
  lede="Sign-ins that are still valid. Revoking one signs that browser out without touching the account."
>
  <Notices feedback={feedback.state} />

  {#key token}
    <Loader load={() => api.query(QUERY)}>
      {#snippet children(data)}
        <Table
          columns={COLUMNS}
          count={data.sessions.length}
          empty="Nobody is signed in right now."
        >
          {#snippet rows()}
            {#each data.sessions as session (session.id)}
              <tr class="hover">
                <td>
                  <Link to={`/actors/${session.actor.uuid}`} class="link link-hover font-medium">
                    {session.actor.nickname}
                  </Link>
                </td>
                <td class="text-xs">
                  <div class="font-mono">{session.ipAddress ?? "—"}</div>
                  <div class="max-w-md truncate opacity-50">{session.userAgent ?? ""}</div>
                </td>
                <td class="text-xs opacity-70" title={moment(session.authenticatedAt)}>
                  {since(session.authenticatedAt)}
                </td>
                <td class="text-xs opacity-70">{day(session.expiresAt)}</td>
                <td class="text-right">
                  <button
                    type="button"
                    class="btn btn-xs btn-error btn-outline"
                    onclick={() => revoke(session)}
                  >
                    Revoke
                  </button>
                </td>
              </tr>
            {/each}
          {/snippet}
        </Table>
      {/snippet}
    </Loader>
  {/key}
</Page>
