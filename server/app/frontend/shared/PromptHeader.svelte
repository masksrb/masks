<script>
let { login } = $props();

const client = $derived(login.auth.client);

const title = $derived(
  client?.name
    ? login.t("heading_to", { client: client.name })
    : login.t("heading"),
);
</script>

<div class="prompt-head">
  <h1 class="prompt-title">{title}</h1>
</div>
