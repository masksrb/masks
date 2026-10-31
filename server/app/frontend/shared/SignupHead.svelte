<script>
import Head from "./Head.svelte";
import Steps from "./Steps.svelte";

let { login, at } = $props();

const tenant = $derived(login.auth.tenant?.name ?? "");
const signingUp = $derived(login.auth.signingUp ?? { steps: [] });
</script>

{#if signingUp.firstRun}
  <Head {login} title={login.t("setup_title")} name={tenant} cap={login.t("setup_cap")} />
{:else}
  <Head {login} title={login.t("signup_title")} />
{/if}

<Steps {login} steps={signingUp.steps} at={at ?? signingUp.steps.length} />
