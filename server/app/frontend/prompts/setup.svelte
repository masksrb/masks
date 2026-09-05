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

const filled = $derived([
  nickname.trim().length > 0,
  email.trim().length > 0,
  password.length >= minimum,
]);

const done = $derived(filled.filter(Boolean).length);

const secret = $derived(
  password.length === 0
    ? ""
    : password.length >= minimum
      ? "set"
      : `${password.length} of ${minimum}`,
);

const valid = $derived(done === 3 && (!needsToken || token.length > 0));

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("setup", { token, nickname, email, password });
  }
}
</script>

<div class="ceremony">
  <aside class="record">
    <span class="record-cap">Creating</span>

    <div class="rec-rows">
      <div class="rec-row">
        <span class="rec-key">owner</span>
        <span class="rec-val" class:rec-val-pending={!filled[0]}>
          {nickname.trim() || "—"}
        </span>
      </div>
      <div class="rec-row">
        <span class="rec-key">email</span>
        <span class="rec-val" class:rec-val-pending={!filled[1]}>
          {email.trim() || "—"}
        </span>
      </div>
      <div class="rec-row">
        <span class="rec-key">password</span>
        <span class="rec-val" class:rec-val-pending={!filled[2]}>
          {secret || "—"}
        </span>
      </div>
      <div class="rec-row">
        <span class="rec-key">tenant</span>
        <span class="rec-val rec-val-fixed">{tenant}</span>
      </div>
      <div class="rec-row">
        <span class="rec-key">role</span>
        <span class="rec-val rec-val-fixed">owner</span>
      </div>
    </div>

    <div class="rec-meter">
      <div class="rec-bar">
        {#each [0, 1, 2] as step (step)}
          <span class="rec-seg" class:rec-seg-on={step < done}></span>
        {/each}
      </div>
      <span class="rec-count">{done} of 3</span>
    </div>
  </aside>

  <div class="flow">
    <div class="prompt-head">
      <span class="record-cap">First run</span>
      <h1 class="prompt-title">Create the owner</h1>
    </div>

    <form {onsubmit} class="flow">
      {#if needsToken}
        <label class="field">
          <span class="field-label">Setup token</span>
          <input
            type="password"
            name="token"
            class="control"
            autocomplete="off"
            bind:value={token}
          />
        </label>
      {/if}

      <label class="field">
        <span class="field-label">Username</span>
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

      <label class="field">
        <span class="field-label">Email</span>
        <input
          type="email"
          name="email"
          class="control"
          autocomplete="email"
          bind:value={email}
        />
      </label>

      <label class="field">
        <span class="field-label">Password</span>
        <input
          type="password"
          name="password"
          class="control"
          autocomplete="new-password"
          bind:value={password}
        />
        <span class="field-hint">At least {minimum} characters.</span>
      </label>

      <button type="submit" class="action" disabled={!valid || login.loading}>
        {#if login.loading}<span class="spinner"></span>{/if}
        {login.loading ? "Creating" : "Create the owner"}
      </button>
    </form>

    <p class="aside">This screen will not appear again.</p>
  </div>
</div>
