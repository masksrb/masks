<script>
/**
 * @typedef {Object} Props
 * @property {any} heading
 * @property {any} client
 * @property {any} redirectUri
 * @property {string} [prefix]
 * @property {string} [suffix]
 * @property {import('svelte').Snippet} [subheading]
 * @property {import('svelte').Snippet} [logo]
 */

/** @type {Props} */
let {
  heading,
  client,
  redirectUri,
  prefix = "to ",
  suffix = "",
  subheading,
  logo,
  class: cls,
} = $props();
</script>

<div class={`flex items-center gap-3 ${cls}`}>
  <div class="flex flex-col grow">
    <h2
      class="text-black dark:text-white text-2xl md:text-3xl font-bold md:mb-1"
    >
      {#if typeof heading == "function"}
        {@render heading()}
      {:else}
        {heading}
      {/if}
    </h2>

    <h1 class="text-xl md:text-2xl">
      {#if subheading}{@render subheading()}{:else if client}
        {prefix}
        {client.name}
        {suffix}
      {/if}
    </h1>
  </div>

  {#if logo}{@render logo()}{:else if client?.logo}
    <div
      class="w-[45px] h-[45px] md:w-[65px] md:h-[65px] rounded-lg overflow-hidden"
    >
      <img src={client.logo} alt={client.name} class="object-cover" />
    </div>
  {/if}
</div>
