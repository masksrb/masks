<script>
let { settings } = $props();
</script>

<div class="cols gap-6 justify-center">
  {#if settings?.themeHomepage}
    <a href={settings?.themeHomepage} class="btn btn-lg btn-primary">
      Go home
    </a>
  {/if}
  <button onclick={() => history.back()} class="btn btn-neutral btn-lg">
    Go back
  </button>
</div>
