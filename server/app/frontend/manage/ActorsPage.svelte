<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day, joined } from "./lib/format.js";
  import Card from "./ui/Card.svelte";
  import Field from "./ui/Field.svelte";
  import Link from "./ui/Link.svelte";
  import Loader from "./ui/Loader.svelte";
  import Notices from "./ui/Notices.svelte";
  import Page from "./ui/Page.svelte";
  import Row from "./ui/Row.svelte";
  import Search from "./ui/Search.svelte";
  import Table from "./ui/Table.svelte";

  let { api } = $props();

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

  const COLUMNS = ["Nickname", "Email", "Second factor", "Scopes", "Last seen"];

  const feedback = createFeedback();

  let search = $state("");
  let query = $state("");
  let token = $state(0);

  let inviting = $state(false);
  let nickname = $state("");
  let email = $state("");
  let busy = $state(false);
  let invited = $state(null);

  const stamp = $derived(`${query}:${token}`);

  function open() {
    nickname = "";
    email = "";
    invited = null;
    inviting = true;
    feedback.clear();
  }

  function close() {
    inviting = false;
    feedback.clear();
  }

  async function send() {
    busy = true;

    const data = await feedback.attempt(() => api.query(INVITE, { nickname, email }));

    busy = false;

    if (!data) return;

    invited = data.inviteActor;
    inviting = false;
    token += 1;
  }
</script>

<Page
  title="Actors"
  lede="Everyone who can sign in through this server, and what each of them may be granted."
>
  {#snippet actions()}
    <Search
      bind:value={search}
      label="Search actors"
      placeholder="nickname, email or name"
      onsearch={() => (query = search)}
    />
    <button type="button" class="btn btn-primary btn-sm" onclick={open}>Invite somebody</button>
  {/snippet}

  <Notices feedback={feedback.state} />

  {#if inviting}
    <Card
      title="Invite somebody"
      lede="They choose their own password from a one-time link. Nothing is granted until they accept."
    >
      <div class="grid gap-3 sm:grid-cols-2">
        <Field
          label="Username"
          bind:value={nickname}
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          placeholder="ada"
        />
        <Field label="Email" type="email" bind:value={email} placeholder="ada@example.com" />
      </div>

      <div class="flex gap-2">
        <button
          type="button"
          class="btn btn-primary btn-sm"
          disabled={busy || !nickname.trim() || !email.trim()}
          onclick={send}
        >
          {busy ? "Sending..." : "Send the invitation"}
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onclick={close}>Cancel</button>
      </div>
    </Card>
  {/if}

  {#if invited}
    <Card title="Invitation sent">
      {#if invited.delivered}
        <p class="max-w-prose text-sm opacity-70">
          The link was emailed. It is not shown here, so that accepting it proves the address.
        </p>
      {:else}
        <p class="max-w-prose text-sm opacity-70">
          No mailer is configured, so pass this link along yourself. It works once.
        </p>
        <p class="rounded bg-base-200 px-2 py-1 font-mono text-xs break-all">{invited.url}</p>
      {/if}
    </Card>
  {/if}

  {#key stamp}
    <Loader load={() => api.query(QUERY, { search: query || null })}>
      {#snippet children(data)}
        <Table
          columns={COLUMNS}
          count={data.actors.length}
          empty={query
            ? `No actor matches “${query}”.`
            : "Nobody can sign in yet. Invite the first person."}
        >
          {#snippet rows()}
            {#each data.actors as actor (actor.uuid)}
              <Row to={`/actors/${actor.uuid}`}>
                <td>
                  <Link to={`/actors/${actor.uuid}`} class="link link-hover font-medium">
                    {actor.nickname}
                  </Link>
                  {#if actor.name}
                    <div class="text-xs opacity-50">{actor.name}</div>
                  {/if}
                </td>
                <td class="text-sm">
                  {actor.email ?? "—"}
                  {#if actor.email && !actor.emailVerified}
                    <span class="badge badge-warning badge-xs ml-1">unconfirmed</span>
                  {/if}
                </td>
                <td>
                  {#if actor.otpEnabled}
                    <span class="badge badge-success badge-sm">authenticator</span>
                    <span class="ml-1 text-xs opacity-60">
                      {actor.backupCodesRemaining} backup codes
                    </span>
                  {:else}
                    <span class="badge badge-ghost badge-sm">password only</span>
                  {/if}
                </td>
                <td class="font-mono text-xs">{joined(actor.scopes)}</td>
                <td class="text-xs opacity-70">
                  {#if !actor.activated}
                    <span class="badge badge-info badge-sm">invited</span>
                  {:else}
                    {day(actor.lastLoginAt, "never")}
                  {/if}
                </td>
              </Row>
            {/each}
          {/snippet}
        </Table>
      {/snippet}
    </Loader>
  {/key}
</Page>
