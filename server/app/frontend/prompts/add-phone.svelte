<script>
import Action from "../shared/Action.svelte";
import ConfirmHead from "../shared/ConfirmHead.svelte";

let { login } = $props();

let phone = $state("");

const valid = $derived(/^\+?[\d\s().-]{7,}$/.test(phone.trim()));

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) login.submit("confirm:add-phone", { phone });
}
</script>

<ConfirmHead {login} title={login.t("title")} lede={login.t("lede")} />

<form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
  <label class="field">
    <span class="field-label">{login.t("phone")}</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="tel"
      name="phone"
      class="control"
      autocomplete="tel"
      placeholder="+15551234567"
      autofocus
      bind:value={phone}
    />
    <span class="field-hint">{login.t("hint")}</span>
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
