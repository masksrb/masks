<script>
  import Link from "./Link.svelte";

  let { title, lede = null, id = null, back = null, hero = false, actions, children } = $props();
</script>

<div class="flex flex-col gap-6">
  {#if back}
    <div>
      <Link to={back.to} class="link link-hover text-sm opacity-70">&larr; {back.label}</Link>
    </div>
  {/if}

  <header class="flex flex-wrap items-end justify-between gap-x-6 gap-y-4">
    <div class="flex min-w-0 flex-col gap-2">
      <h1 class="headline" class:headline-hero={hero}>{title}</h1>

      {#if id}
        <p class="stamp">{id}</p>
      {/if}

      {#if lede}
        <p class="deck">{lede}</p>
      {/if}
    </div>

    {#if actions}
      <div class="flex flex-wrap items-center gap-2">{@render actions()}</div>
    {/if}
  </header>

  {@render children()}
</div>
