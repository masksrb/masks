<script>
  import Link from "./Link.svelte";

  let { title, lede = null, id = null, back = null, hero = false, lead, after, actions, children } = $props();

  let heading;

  $effect(() => {
    document.title = title;
  });

  $effect(() => {
    heading?.focus({ preventScroll: true });
  });
</script>

<div class="console-page">
  {#if back}
    <div>
      <Link to={back.to} class="link link-hover text-sm opacity-85">&larr; {back.label}</Link>
    </div>
  {/if}

  <header class="flex flex-wrap items-end justify-between gap-x-6 gap-y-4">
    <div class="flex min-w-0 items-start gap-4">
      {#if lead}{@render lead()}{/if}

      <div class="flex min-w-0 flex-col gap-2">
        <div class="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1">
          <h1 class="headline min-w-0 break-words outline-none" class:headline-hero={hero} tabindex="-1" bind:this={heading}>{title}</h1>
          {#if after}{@render after()}{/if}
        </div>

        {#if id}
          <p class="stamp">{id}</p>
        {/if}

        {#if lede}
          <p class="deck">{lede}</p>
        {/if}
      </div>
    </div>

    {#if actions}
      <div class="flex w-full flex-wrap items-center gap-2 sm:w-auto">{@render actions()}</div>
    {/if}
  </header>

  {@render children()}
</div>
