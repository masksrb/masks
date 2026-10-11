<script>
  import { t } from "./lib/copy.js";
  import MailTemplate from "./MailTemplate.svelte";
  import Loader from "./ui/Loader.svelte";
  import Tip from "./ui/Tip.svelte";

  let { api } = $props();

  const PREVIEWS = `
    query MailPreviews($client: ID) {
      mailPreviews(client: $client) { key name journey heading subject from to html text }
      clients { clientId name approvedAt }
      mailTemplates { kind subject message placeholders }
    }
  `;

  const GROUPS = ["sign_in", "manage", "account", "system"];

  const templated = (key) => (key === "invitation_organization" ? "invitation" : key);

  let client = $state("");
  let version = $state(0);
  let chosen = $state(null);
  let showing = $state("html");

  function fit(event) {
    const frame = event.currentTarget;

    frame.style.height = `${frame.contentDocument.documentElement.scrollHeight}px`;
  }
</script>

<div class="console-page">
  {#key `${client}:${version}`}
    <Loader load={() => api.query(PREVIEWS, { client: client || null })}>
      {#snippet children(data)}
        {@const previews = data.mailPreviews}
        {@const shown = previews.find((preview) => preview.key === chosen) ?? previews[0]}
        {@const templates = Object.fromEntries(data.mailTemplates.map((template) => [template.kind, template]))}
        {@const template = templates[templated(shown.key)]}

        <div class="mail">
          <nav class="mail-list" aria-label={t("emails.list")}>
            {#each GROUPS as journey (journey)}
              {@const members = previews.filter((preview) => preview.journey === journey)}

              {#if members.length}
                <div class="mail-group">
                  <div class="flex items-center gap-2">
                    <span class="term">{t(`emails.groups.${journey}.title`)}</span>
                    <Tip text={t(`emails.groups.${journey}.help`)} label={t(`emails.groups.${journey}.about`)} />
                  </div>

                  {#if journey === "sign_in"}
                    <select
                      class="select select-sm w-full"
                      aria-label={t("emails.app")}
                      value={client}
                      onchange={(event) => (client = event.currentTarget.value)}
                    >
                      <option value="">{t("emails.no_app")}</option>
                      {#each data.clients as each (each.clientId)}
                        <option value={each.clientId}>{each.approvedAt ? each.name : t("emails.not_approved", { name: each.name })}</option>
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
                <p class="hint">
                  {t("emails.headed", {
                    heading: shown.heading,
                    from: shown.from || t("emails.no_sender"),
                    to: shown.to,
                  })}
                </p>
              </div>

              <div class="range" role="group" aria-label={t("emails.part")}>
                <button type="button" aria-pressed={showing === "html"} onclick={() => (showing = "html")}>{t("emails.html")}</button>
                <button type="button" aria-pressed={showing === "text"} onclick={() => (showing = "text")}>{t("emails.text")}</button>
              </div>
            </header>

            <div class="mail-words">
              {#if template}
                {#key template.kind}
                  <MailTemplate {api} template={template} title={shown.name} onsaved={() => version++} />
                {/key}
              {/if}

              <MailTemplate {api} template={templates.signature} title={t("emails.signature")} onsaved={() => version++} />
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
</div>
