<script>
  import { t } from "./lib/copy.js";
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
      blank ? t("mail_wording.reset", { title }) : t("mail_wording.saved", { title }),
    );

    busy = false;

    if (done) onsaved?.();
  }
</script>

<details class="mail-wording" open={custom || undefined}>
  <summary class="term">
    {t(signature ? "mail_wording.signature" : "mail_wording.wording")}{custom ? t("mail_wording.customized") : ""}
  </summary>

  <form
    class="flex flex-col gap-3 pt-3"
    onsubmit={(event) => {
      event.preventDefault();
      save();
    }}
  >
    <Notices feedback={feedback.state} />

    {#if !signature}
      <Field
        label={t("mail_wording.subject")}
        bind:value={subject}
        maxlength="150"
        placeholder={t("mail_wording.subject_placeholder")}
      />
    {/if}

    <label class="flex flex-col gap-1.5">
      <span class="field-label">{t(signature ? "mail_wording.closing" : "mail_wording.opening")}</span>
      <textarea
        class="textarea textarea-sm w-full"
        rows="4"
        maxlength="2000"
        placeholder={t(signature ? "mail_wording.closing_placeholder" : "mail_wording.opening_placeholder")}
        bind:value={message}
      ></textarea>
      <span class="hint">
        {t("mail_wording.hint", { names })}
        {#if !signature}{t("mail_wording.hint_more")}{/if}
      </span>
    </label>

    <div class="flex gap-2">
      <button type="submit" class="btn btn-sm btn-primary" disabled={busy}>{t("mail_wording.save")}</button>
      {#if custom}
        <button type="button" class="btn btn-sm btn-ghost" disabled={busy} onclick={() => save(true)}>
          {t("mail_wording.use_default")}
        </button>
      {/if}
    </div>
  </form>
</details>
