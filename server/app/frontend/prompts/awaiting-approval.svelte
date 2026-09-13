<script>
import Action from "../shared/Action.svelte";
import ConfirmHead from "../shared/ConfirmHead.svelte";

let { login } = $props();

$effect(() => {
  const timer = setInterval(() => {
    if (!login.loading) login.submit("confirm:check", {});
  }, 15000);

  return () => clearInterval(timer);
});
</script>

<ConfirmHead {login} title={login.t("title")} lede={login.t("lede")} />

<p class="waiting aside">{login.t("waiting")}</p>

<Action {login} quiet label={login.t("check")} busy={login.loading} onclick={() => login.submit("confirm:check", {})} />
