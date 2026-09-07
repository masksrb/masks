<script>
let { login } = $props();
</script>

<div class="whom">
  <span class="whom-name">{login.auth.identifier}</span>

  <button
    type="button"
    class="textlink"
    disabled={login.loading}
    onclick={() => login.startOver()}
  >
    {login.t("not_you")}
  </button>
</div>
