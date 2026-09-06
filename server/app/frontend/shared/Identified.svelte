<script>
let { login } = $props();
</script>

<div class="chip">
  <span class="chip-mono">{login.auth.identifier}</span>
  <button
    type="button"
    class="textlink chip-action"
    disabled={login.loading}
    onclick={() => login.startOver()}>{login.t("not_you")}</button
  >
</div>
