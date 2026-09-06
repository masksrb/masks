<script>
let { login } = $props();

let password = $state("");

const invitation = $derived(login.auth.invitation ?? {});
const minimum = $derived(invitation.minimum ?? 8);

const valid = $derived(password.length >= minimum);

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("accept-invitation", { password });
  }
}
</script>

<div class="prompt-head">
  <h1 class="prompt-title">{login.t("title")}</h1>
  {#if invitation.invitedBy}
    <p class="prompt-lede">
      {login.t("invited_by", { nickname: invitation.invitedBy })}
    </p>
  {/if}
</div>

<form {onsubmit} class="flow">
  <label class="field">
    <span class="field-label">{login.t("username")}</span>
    <input
      type="text"
      class="control"
      autocomplete="username"
      value={invitation.nickname ?? ""}
      readonly
    />
  </label>

  {#if invitation.email}
    <label class="field">
      <span class="field-label">{login.t("email")}</span>
      <input type="email" class="control" value={invitation.email} readonly />
    </label>
  {/if}

  <label class="field">
    <span class="field-label">{login.t("password")}</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="password"
      name="password"
      class="control"
      autocomplete="new-password"
      autofocus
      bind:value={password}
    />
    <span class="field-hint">{login.t("hint", { minimum })}</span>
  </label>

  <button type="submit" class="action" disabled={!valid || login.loading}>
    {#if login.loading}<span class="spinner"></span>{/if}
    {login.loading ? login.t("working") : login.t("continue")}
  </button>
</form>
