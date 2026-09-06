<script>
let { login } = $props();

let token = $state("");
let nickname = $state("");
let email = $state("");
let password = $state("");

const setup = $derived(login.auth.setup ?? {});
const minimum = $derived(setup.minimum ?? 8);
const needsToken = $derived(setup.token === true);
const tenant = $derived(login.auth.tenant?.name ?? "");
const docs = $derived(login.auth.docs);
const origin = typeof location === "undefined" ? "" : location.origin;

const title = $derived(
  tenant ? login.t("title_named", { tenant }) : login.t("title"),
);

const steps = $derived(
  (needsToken ? [token.length > 0] : []).concat(
    nickname.trim().length > 0,
    email.trim().length > 0,
    password.length >= minimum,
  ),
);

const valid = $derived(steps.every(Boolean));

const stops = $derived(steps.length === 4 ? [1, 2, 3, 4] : [1, 2, 4]);

const step = (index) =>
  `ledger-row ledger-step ledger-step-${stops[index]}` +
  (steps[index] ? " ledger-step-done" : "");

const initial = (name) => (name ? name.trim().slice(0, 1).toUpperCase() : "");

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("setup", { token, nickname, email, password });
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

  <div class="prompt-head">
    <span class="record-cap">{login.t("cap")}</span>
    <h1 class="prompt-title">{title}</h1>
  </div>

  <div class="note note-plain" role="status">{login.t("note")}</div>

  <form {onsubmit} class="flow">
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
        <span class="ledger-label">{login.t("username")}</span>
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

      <label class={step(needsToken ? 3 : 2)}>
        <span class="ledger-label">{login.t("password")}</span>
        <input
          type="password"
          name="password"
          class="control"
          autocomplete="new-password"
          bind:value={password}
        />
        <span class="field-hint">{login.t("password_hint", { minimum })}</span>
      </label>

      <div class="ledger-row">
        <span class="ledger-label">{login.t("origin")}</span>
        <span class="ledger-value aside-mono">{origin}</span>
      </div>
    </div>

    <button type="submit" class="action" disabled={!valid || login.loading}>
      {#if login.loading}<span class="spinner"></span>{/if}
      {login.loading ? login.t("working") : login.t("submit")}
    </button>
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
