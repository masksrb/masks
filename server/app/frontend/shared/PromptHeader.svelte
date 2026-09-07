<script>
import Head from "./Head.svelte";

let { login, tone = null } = $props();

const client = $derived(login.auth.client);

const title = $derived(
  client?.name
    ? login.t("heading_to", { client: client.name })
    : login.t("heading"),
);
</script>

<Head {login} {title} {tone} />
