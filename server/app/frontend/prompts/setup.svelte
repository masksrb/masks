<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";

let { login } = $props();

const setup = $derived(login.auth.setup ?? {});
const needsToken = $derived(setup.token === true);
const tenant = $derived(login.auth.tenant?.name ?? "");
const docs = $derived(login.auth.docs);
const origin = typeof location === "undefined" ? "" : location.origin;

let token = $state("");
let nickname = $state(setup.nickname ?? "");
let email = $state(setup.email ?? "");

const steps = $derived(
  (needsToken ? [token.length > 0] : []).concat(
    nickname.trim().length > 0,
    email.trim().length > 0,
  ),
);

const valid = $derived(steps.every(Boolean));

const stops = $derived(steps.length === 3 ? [1, 2, 3] : [1, 2]);

const step = (index) =>
  `ledger-row ledger-step ledger-step-${stops[index]}` +
  (steps[index] ? " ledger-step-done" : "");

const initial = (name) => (name ? name.trim().slice(0, 1).toUpperCase() : "");

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("setup", { token, nickname, email });
  }
}
</script>

<div class="setup flow" class:setup-ready={valid}>
  <div class="auth-pair">
    <span
      class="auth-mark auth-mark-client"
      class:auth-mark-pending={!nickname.trim()}
      aria-hidden="true">{initial(nickname)}</span>
    <span class="auth-wire"></span>
    <span class="auth-mark" aria-hidden="true">{initial(tenant)}</span>
  </div>

  <Head
    {login}
    title={login.t("title")}
    name={tenant}
    cap={login.t("cap")} />

  <div
    class="note"
    class:note-warn={!valid}
    class:note-plain={valid}
    role="status">
    <span>{login.t("note")} <strong>{login.t("note_keep")}</strong></span>
  </div>

  <form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
    <div class="slab">
      {#if needsToken}
        <label class={step(0)}>
          <span class="ledger-label">{login.t("token")}</span>
          <input
            type="password"
            name="token"
            class="control"
            autocomplete="off"
            bind:value={token}
          />
          <span class="field-hint">{login.t("token_hint")}</span>
        </label>
      {/if}

      <label class={step(needsToken ? 1 : 0)}>
        <span class="ledger-label">{login.t("nickname")}</span>
        <!-- svelte-ignore a11y_autofocus -->
        <input
          type="text"
          name="nickname"
          class="control"
          autocomplete="username"
          autocapitalize="none"
          autocorrect="off"
          spellcheck="false"
          autofocus
          bind:value={nickname}
        />
      </label>

      <label class={step(needsToken ? 2 : 1)}>
        <span class="ledger-label">{login.t("email")}</span>
        <input
          type="email"
          name="email"
          class="control"
          autocomplete="email"
          bind:value={email}
        />
      </label>

      <div class="ledger-row">
        <span class="ledger-label">{login.t("origin")}</span>
        <span class="ledger-value aside-mono">{origin}</span>
      </div>
    </div>

    <Action
      {login}
      type="submit"
      ready={valid}
      busy={login.loading}
      label={login.t("continue")}
      working={login.t("working")}
    />
  </form>

  <p class="aside">
    {login.t("once")}
    {#if docs}
      <a class="textlink" href={docs} rel="noopener" target="_blank"
        >{login.t("docs")}</a
      >
    {/if}
  </p>
</div>
