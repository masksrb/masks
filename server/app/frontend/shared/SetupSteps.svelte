<script>
let { login, at } = $props();

const tabs = $derived([
  login.t("tab_identification"),
  login.t("tab_credentials"),
  login.t("tab_configuration"),
]);
</script>

<nav class="tabset" aria-label={login.t("tabs")}>
  {#each tabs as text, index (text)}
    {@const place = index + 1}
    <span
      class="tabset-tab"
      class:tabset-done={place < at}
      class:tabset-now={place === at}
      aria-current={place === at ? "step" : undefined}>
      {text}
    </span>
  {/each}
</nav>
