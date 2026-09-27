<script>
  import Loader from "./ui/Loader.svelte";
  import Page from "./ui/Page.svelte";

  let { api } = $props();

  const QUERY = `query MailPreviews { mailPreviews { key name subject from to html text } }`;

  let chosen = $state(null);
  let showing = $state("html");
</script>

<Page
  title="Email"
  lede="Every email masks sends from this tenant, rendered from its templates with sample people. Addresses and links use this tenant's own."
>
  <Loader load={() => api.query(QUERY)}>
    {#snippet children(data)}
      {@const previews = data.mailPreviews}
      {@const shown = previews.find((preview) => preview.key === chosen) ?? previews[0]}

      <div class="mail">
        <nav class="mail-list" aria-label="Emails">
          {#each previews as preview (preview.key)}
            <button
              type="button"
              class="mail-item"
              aria-current={preview.key === shown.key ? "true" : undefined}
              onclick={() => (chosen = preview.key)}
            >
              {preview.name}
            </button>
          {/each}
        </nav>

        <article class="mail-view">
          <header class="mail-head">
            <div class="flex min-w-0 flex-col gap-1">
              <h2 class="mail-subject">{shown.subject}</h2>
              <p class="hint">From {shown.from || "no sender configured"} to {shown.to}</p>
            </div>

            <div class="range" role="group" aria-label="Which part">
              <button type="button" aria-pressed={showing === "html"} onclick={() => (showing = "html")}>HTML</button>
              <button type="button" aria-pressed={showing === "text"} onclick={() => (showing = "text")}>Text</button>
            </div>
          </header>

          {#if showing === "html" && shown.html}
            <iframe class="mail-frame" title={shown.subject} sandbox="" srcdoc={shown.html}></iframe>
          {:else}
            <pre class="mail-text">{shown.text ?? ""}</pre>
          {/if}
        </article>
      </div>
    {/snippet}
  </Loader>
</Page>
