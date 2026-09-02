<script>
  import Loader from "./Loader.svelte";

  let { api, router } = $props();

  let search = $state("");

  const QUERY = `
    query Actors($search: String) {
      actors(search: $search) {
        uuid nickname name email emailVerified otpEnabled backupCodesRemaining
        lastLoginAt scopes activated invitedAt
      }
    }
  `;

  const INVITE = `
    mutation Invite($nickname: String!, $email: String!) {
      inviteActor(nickname: $nickname, email: $email) {
        delivered url actor { uuid }
      }
    }
  `;

  let token = $state(0);

  let inviting = $state(false);
  let nickname = $state("");
  let email = $state("");
  let busy = $state(false);
  let failure = $state(null);
  let invited = $state(null);

  function open() {
    nickname = "";
    email = "";
    failure = null;
    invited = null;
    inviting = true;
  }

  async function send() {
    busy = true;
    failure = null;

    try {
      const data = await api.query(INVITE, { nickname, email });
      invited = data.inviteActor;
      inviting = false;
      token += 1;
    } catch (error) {
      failure = error.message;
    } finally {
      busy = false;
    }
  }
</script>

<div class="flex items-center gap-3 mb-4">
  <h1 class="text-xl font-bold flex-1">Actors</h1>
  <input
    class="input input-sm input-bordered"
    placeholder="nickname, email or name"
    bind:value={search}
    onkeydown={(e) => e.key === "Enter" && (token += 1)}
  />
  <button class="btn btn-primary btn-sm" onclick={open}>Invite</button>
</div>

{#if inviting}
  <div class="bg-base-100 rounded-box p-4 mb-4 flex flex-col gap-3">
    <h2 class="font-medium">Invite somebody</h2>

    {#if failure}
      <p class="text-sm text-error">{failure}</p>
    {/if}

    <div class="flex flex-wrap gap-3">
      <input
        class="input input-sm input-bordered"
        placeholder="username"
        autocapitalize="none"
        autocorrect="off"
        spellcheck="false"
        bind:value={nickname}
      />
      <input
        class="input input-sm input-bordered"
        type="email"
        placeholder="email"
        bind:value={email}
      />
      <button
        class="btn btn-primary btn-sm"
        disabled={busy || !nickname.trim() || !email.trim()}
        onclick={send}
      >
        {busy ? "Inviting..." : "Send the invitation"}
      </button>
      <button class="btn btn-ghost btn-sm" onclick={() => (inviting = false)}>Cancel</button>
    </div>
  </div>
{/if}

{#if invited}
  <div class="bg-base-100 rounded-box p-4 mb-4 flex flex-col gap-2">
    {#if invited.delivered}
      <p class="text-sm">The invitation was emailed. The link is not shown here, so that accepting it proves the address.</p>
    {:else}
      <p class="text-sm">No mailer is configured, so send this link yourself. It works once.</p>
      <p class="font-mono text-xs break-all bg-base-200 rounded px-2 py-1">{invited.url}</p>
    {/if}
  </div>
{/if}

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
                <td class="text-xs opacity-70">
                  {#if !actor.activated}
                    <span class="badge badge-info badge-sm">invited</span>
                  {:else}
                    {actor.lastLoginAt?.slice(0, 10) ?? "never"}
                  {/if}
                </td>
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
