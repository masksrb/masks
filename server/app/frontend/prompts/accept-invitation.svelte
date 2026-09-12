<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";

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

<Head
  {login}
  title={login.t("title")}
  lede={invitation.invitedBy
    ? login.t("invited_by", { nickname: invitation.invitedBy })
    : null}
/>

<form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
  <label class="field">
    <span class="field-label">{login.t("nickname")}</span>
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

  <Action
    {login}
    type="submit"
    ready={valid}
    busy={login.loading}
    label={login.t("continue")}
    working={login.t("working")}
  />
</form>
