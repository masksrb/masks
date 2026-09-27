<script>
import { initial } from "../lib/initial.js";
import Head from "./Head.svelte";
import Steps from "./Steps.svelte";

let { login, at, mark = "" } = $props();

const tenant = $derived(login.auth.tenant?.name ?? "");
const signingUp = $derived(login.auth.signingUp ?? { steps: [] });

</script>

<div class="auth-pair">
  <span class="auth-mark auth-mark-client" class:auth-mark-pending={!mark.trim()} aria-hidden="true"
    >{initial(mark)}</span>
  <span class="auth-wire"></span>
  {#if signingUp.firstRun}
    <img src="/masks-public/icon.svg" alt="" class="auth-mark auth-mark-rose" />
  {:else}
    <span class="auth-mark" aria-hidden="true">{initial(tenant)}</span>
  {/if}
</div>

{#if signingUp.firstRun}
  <Head {login} title={login.t("setup_title")} name={tenant} cap={login.t("setup_cap")} />
{:else}
  <Head {login} title={login.t("signup_title")} name={tenant} />
{/if}

<Steps {login} steps={signingUp.steps} at={at ?? signingUp.steps.length} />
