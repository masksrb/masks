<script>
import TenantMark from "../shared/TenantMark.svelte";
import ClientMark from "../shared/ClientMark.svelte";
import Head from "../shared/Head.svelte";

let { login } = $props();

const client = $derived(login.client?.name ?? "");

const title = $derived(
  client ? login.t("heading_to", { client }) : login.t("heading"),
);

</script>

<div class="over">
  {#if client}
    <div class="auth-pair">
      <TenantMark tenant={login.auth.tenant} />
      <span class="auth-wire auth-wire-live"></span>
      <ClientMark client={login.client} />
    </div>
  {/if}

  <Head {login} {title} busy lede={login.t("waiting")} />
</div>
