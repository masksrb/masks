<script>
import Head from "./Head.svelte";
import Steps from "./Steps.svelte";

let { login, firstRun, steps, at, mark = "" } = $props();

const tenant = $derived(login.auth.tenant?.name ?? "");

const initial = (name) => (name ? name.trim().slice(0, 1).toUpperCase() : "");
</script>

<div class="auth-pair">
  <span class="auth-mark auth-mark-client" class:auth-mark-pending={!mark.trim()} aria-hidden="true"
    >{initial(mark)}</span>
  <span class="auth-wire"></span>
  <span class="auth-mark" aria-hidden="true">{initial(tenant)}</span>
</div>

{#if firstRun}
  <Head {login} title={login.t("setup_title")} name={tenant} cap={login.t("setup_cap")} />
{:else}
  <Head {login} title={login.t("signup_title")} name={tenant} />
{/if}

<Steps {login} {steps} {at} />
