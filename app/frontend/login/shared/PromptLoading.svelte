<script>
  /**
   * @typedef {Object} Props
   * @property {import('svelte').Snippet} [children]
   */

  /** @type {Props & { [key: string]: any }} */
  let { ...props } = $props();
</script>

<div
  class={`flex h-full w-full align-items-center items-center min-h-[400px] ${props.class}`}
>
  <span class="loading loading-spinner loading-lg mx-auto"></span>
  {@render props.children?.()}
</div>
