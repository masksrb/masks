<div class="flex items-center gap-6">
  {#if settings?.themeHomepage}
    <a href={settings?.themeHomepage} class="btn btn-lg btn-primary">
      Go home
    </a>
  {:else}
    <button onclick={() => history.back()} class="btn btn-error btn-lg text-lg">
      Go back
    </button>
  {/if}
</div>
