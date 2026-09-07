<script>
import Head from "../shared/Head.svelte";

let { login } = $props();

const client = $derived(login.client?.name ?? "");
const tenant = $derived(login.auth.tenant?.name ?? "");

const title = $derived(
  client ? login.t("heading_to", { client }) : login.t("heading"),
);

const initial = (name) => (name ? name.trim().slice(0, 1).toUpperCase() : "");
</script>

<div class="over">
  {#if client}
    <div class="auth-pair">
      <span class="auth-mark" aria-hidden="true">{initial(tenant)}</span>
      <span class="auth-wire auth-wire-live"></span>
      <span class="auth-mark auth-mark-client" aria-hidden="true"
        >{initial(client)}</span
      >
    </div>
  {/if}

  <Head {login} {title} busy lede={login.t("waiting")} />
</div>
