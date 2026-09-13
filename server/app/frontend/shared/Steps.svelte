<script>
let { login, steps = [], at } = $props();
</script>

<nav class="tabset" aria-label={login.t("tabs")}>
  {#each steps as step, index (step)}
    {@const place = index + 1}
    <span
      class="tabset-tab"
      class:tabset-done={place < at}
      class:tabset-now={place === at}
      aria-current={place === at ? "step" : undefined}>
      {login.t(`tab_${step}`)}
    </span>
  {/each}
</nav>
