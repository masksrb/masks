<script>
  import Loader from "./Loader.svelte";

  let { api, router } = $props();

  let search = $state("");

  const QUERY = `
    query Actors($search: String) {
      actors(search: $search) {
        uuid nickname name email emailVerified otpEnabled backupCodesRemaining lastLoginAt scopes
      }
    }
  `;

  let token = $state(0);
</script>

<div class="flex items-center gap-3 mb-4">
  <h1 class="text-xl font-bold flex-1">Actors</h1>
  <input
    class="input input-sm input-bordered"
    placeholder="nickname, email or name"
    bind:value={search}
    onkeydown={(e) => e.key === "Enter" && (token += 1)}
  />
</div>

{#key token}
  <Loader load={() => api.query(QUERY, { search: search || null })}>
    {#snippet children(data)}
      <div class="overflow-x-auto bg-base-100 rounded-box">
        <table class="table">
          <thead>
            <tr>
              <th>Nickname</th><th>Email</th><th>Second factor</th><th>Scopes</th><th>Last seen</th>
            </tr>
          </thead>
          <tbody>
            {#each data.actors as actor (actor.uuid)}
              <tr class="hover cursor-pointer" onclick={() => router.go(`/actors/${actor.uuid}`)}>
                <td class="font-medium">{actor.nickname}</td>
                <td class="text-sm">
                  {actor.email ?? "—"}
                  {#if actor.email && !actor.emailVerified}
                    <span class="badge badge-warning badge-xs ml-1">unverified</span>
                  {/if}
                </td>
                <td>
                  {#if actor.otpEnabled}
                    <span class="badge badge-success badge-sm">authenticator</span>
                    <span class="text-xs opacity-60 ml-1">{actor.backupCodesRemaining} codes</span>
                  {:else}
                    <span class="badge badge-ghost badge-sm">password only</span>
                  {/if}
                </td>
                <td class="font-mono text-xs">{actor.scopes.join(" ")}</td>
                <td class="text-xs opacity-70">{actor.lastLoginAt?.slice(0, 10) ?? "never"}</td>
              </tr>
            {/each}
          </tbody>
        </table>

        {#if data.actors.length === 0}
          <p class="p-6 text-sm opacity-70">No actors match that.</p>
        {/if}
      </div>
    {/snippet}
  </Loader>
{/key}
