<script>
  import MailWording from "./MailWording.svelte";
  import Loader from "./ui/Loader.svelte";
  import Page from "./ui/Page.svelte";
  import Tip from "./ui/Tip.svelte";

  let { api } = $props();

  const PREVIEWS = `
    query MailPreviews($client: ID) {
      mailPreviews(client: $client) { key name journey heading subject from to html text }
      clients { clientId name approvedAt }
      mailTemplates { kind subject message placeholders }
    }
  `;

  const GROUPS = [
    ["sign_in", "While signing in", "Sent during a sign-in. When an app sent the person there, an approved app heads the email with its logo and name. A sign-in straight to the account page has no app, and the tenant heads it."],
    ["manage", "From a manager", "Sent when a manager acts in /manage. The tenant heads these."],
    ["account", "From the account page", "Sent when a person changes their own account. The tenant heads these."],
    ["system", "On its own", "Sent by masks without anyone acting, such as security notices and idle warnings. The tenant heads these."],
  ];

  const WORDED = {
    confirmation_code: "confirmation_code",
    email_verification: "email_verification",
    password_reset: "password_reset",
    approval_requested: "approval_requested",
    invitation: "invitation",
    invitation_organization: "invitation",
    organization_invitation: "organization_invitation",
    approved: "approved",
  };

  let client = $state("");
  let version = $state(0);
  let chosen = $state(null);
  let showing = $state("html");

  function fit(event) {
    const frame = event.currentTarget;

    frame.style.height = `${frame.contentDocument.documentElement.scrollHeight}px`;
  }
</script>

<Page title="Email">
  {#key `${client}:${version}`}
    <Loader load={() => api.query(PREVIEWS, { client: client || null })}>
      {#snippet children(data)}
        {@const previews = data.mailPreviews}
        {@const shown = previews.find((preview) => preview.key === chosen) ?? previews[0]}
        {@const templates = Object.fromEntries(data.mailTemplates.map((template) => [template.kind, template]))}
        {@const worded = templates[WORDED[shown.key]]}

        <div class="mail">
          <nav class="mail-list" aria-label="Emails">
            {#each GROUPS as [journey, title, help] (journey)}
              {@const members = previews.filter((preview) => preview.journey === journey)}

              {#if members.length}
                <div class="mail-group">
                  <div class="flex items-center gap-2">
                    <span class="term">{title}</span>
                    <Tip text={help} label="About emails sent {title.toLowerCase()}" />
                  </div>

                  {#if journey === "sign_in"}
                    <select
                      class="select select-sm w-full"
                      aria-label="The app being signed in to"
                      value={client}
                      onchange={(event) => (client = event.currentTarget.value)}
                    >
                      <option value="">No app</option>
                      {#each data.clients as each (each.clientId)}
                        <option value={each.clientId}>{each.approvedAt ? each.name : `${each.name} (not approved)`}</option>
                      {/each}
                    </select>
                  {/if}

                  {#each members as preview (preview.key)}
                    <button
                      type="button"
                      class="mail-item"
                      aria-current={preview.key === shown.key ? "true" : undefined}
                      onclick={() => (chosen = preview.key)}
                    >
                      {preview.name}
                    </button>
                  {/each}
                </div>
              {/if}
            {/each}
          </nav>

          <article class="mail-view">
            <header class="mail-head">
              <div class="flex min-w-0 flex-col gap-0.5">
                <h2 class="mail-subject">{shown.subject}</h2>
                <p class="hint">Headed by {shown.heading}, from {shown.from || "no sender configured"} to {shown.to}</p>
              </div>

              <div class="range" role="group" aria-label="Which part">
                <button type="button" aria-pressed={showing === "html"} onclick={() => (showing = "html")}>HTML</button>
                <button type="button" aria-pressed={showing === "text"} onclick={() => (showing = "text")}>Text</button>
              </div>
            </header>

            <div class="mail-words">
              {#if worded}
                {#key worded.kind}
                  <MailWording {api} template={worded} title={shown.name} onsaved={() => version++} />
                {/key}
              {/if}

              <MailWording {api} template={templates.signature} title="The signature" onsaved={() => version++} />
            </div>

            {#if showing === "html" && shown.html}
              <iframe
                class="mail-frame"
                title={shown.subject}
                sandbox="allow-same-origin"
                srcdoc={shown.html}
                onload={fit}
              ></iframe>
            {:else}
              <pre class="mail-text">{shown.text ?? ""}</pre>
            {/if}
          </article>
        </div>
      {/snippet}
    </Loader>
  {/key}
</Page>
