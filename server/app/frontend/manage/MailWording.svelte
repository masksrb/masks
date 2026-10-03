<script>
  import { untrack } from "svelte";
  import { createFeedback } from "./lib/feedback.svelte.js";
  import Field from "./ui/Field.svelte";
  import Notices from "./ui/Notices.svelte";

  let { api, template, title, onsaved } = $props();

  const UPDATE = `
    mutation Word($kind: ID!, $subject: String, $message: String) {
      updateMailTemplate(kind: $kind, subject: $subject, message: $message) { mailTemplate { kind } }
    }
  `;

  const feedback = createFeedback();

  let subject = $state(untrack(() => template.subject) ?? "");
  let message = $state(untrack(() => template.message) ?? "");
  let busy = $state(false);

  const signature = $derived(template.kind === "signature");
  const custom = $derived(Boolean(template.subject || template.message));
  const names = $derived(template.placeholders.map((name) => `{{${name}}}`).join(", "));

  async function save(blank = false) {
    busy = true;

    const done = await feedback.attempt(
      () =>
        api.query(UPDATE, {
          kind: template.kind,
          subject: blank || signature ? "" : subject,
          message: blank ? "" : message,
        }),
      blank ? `${title} uses masks' wording again.` : `${title} saved.`,
    );

    busy = false;

    if (done) onsaved?.();
  }
</script>

<details class="mail-wording" open={custom || undefined}>
  <summary class="term">{signature ? "Signature" : "Wording"}{custom ? " (customized)" : ""}</summary>

  <form
    class="flex flex-col gap-3 pt-3"
    onsubmit={(event) => {
      event.preventDefault();
      save();
    }}
  >
    <Notices feedback={feedback.state} />

    {#if !signature}
      <Field label="Subject" bind:value={subject} maxlength="150" placeholder="The subject masks writes" />
    {/if}

    <label class="flex flex-col gap-1.5">
      <span class="field-label">{signature ? "Closing lines on every email" : "Opening text"}</span>
      <textarea
        class="textarea textarea-sm w-full"
        rows="4"
        maxlength="2000"
        placeholder={signature ? "None" : "The opening masks writes"}
        bind:value={message}
      ></textarea>
      <span class="hint">
        Plain text. A blank line starts a new paragraph. Fills in {names}.
        {#if !signature}masks still adds the button or code, how long it lasts, and the safety lines.{/if}
      </span>
    </label>

    <div class="flex gap-2">
      <button type="submit" class="btn btn-sm btn-primary" disabled={busy}>Save</button>
      {#if custom}
        <button type="button" class="btn btn-sm btn-ghost" disabled={busy} onclick={() => save(true)}>
          Use masks' wording
        </button>
      {/if}
    </div>
  </form>
</details>
