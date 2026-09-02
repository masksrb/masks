<script>
  import Loader from "./Loader.svelte";

  let { api } = $props();

  let token = $state(0);
  let failure = $state(null);

  const QUERY = `
    query Sessions {
      sessions {
        id userAgent ipAddress authenticatedAt expiresAt createdAt
        actor { uuid nickname }
      }
    }
  `;

  async function revoke(id) {
    failure = null;

    try {
      await api.query(
        `mutation Revoke($id: ID!) { revokeSession(id: $id) { session { revokedAt } } }`,
        { id },
      );

      token += 1;
    } catch (thrown) {
      failure = thrown.message;
    }
  }
</script>

<h1 class="text-xl font-bold mb-4">Live sessions</h1>

{#if failure}<div class="alert alert-error text-sm mb-4" role="alert">{failure}</div>{/if}

{#key token}
  <Loader load={() => api.query(QUERY)}>
    {#snippet children(data)}
      <div class="overflow-x-auto bg-base-100 rounded-box">
        <table class="table">
          <thead>
            <tr><th>Actor</th><th>Where from</th><th>Signed in</th><th>Expires</th><th></th></tr>
          </thead>
          <tbody>
            {#each data.sessions as session (session.id)}
              <tr>
                <td class="font-medium">{session.actor.nickname}</td>
                <td class="text-xs">
                  <div class="font-mono">{session.ipAddress ?? "—"}</div>
                  <div class="opacity-50 max-w-md truncate">{session.userAgent ?? ""}</div>
                </td>
                <td class="text-xs opacity-70">{session.authenticatedAt?.slice(0, 16).replace("T", " ")}</td>
                <td class="text-xs opacity-70">{session.expiresAt?.slice(0, 10)}</td>
                <td class="text-right">
                  <button class="btn btn-xs btn-error btn-outline" onclick={() => revoke(session.id)}>
                    Revoke
                  </button>
                </td>
              </tr>
            {/each}
          </tbody>
        </table>

        {#if data.sessions.length === 0}
          <p class="p-6 text-sm opacity-70">No live sessions.</p>
        {/if}
      </div>
    {/snippet}
  </Loader>
{/key}
