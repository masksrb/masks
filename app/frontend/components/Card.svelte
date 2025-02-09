<script>
  /**
   * @typedef {Object} Props
   * @property {import('svelte').Snippet} [children]
   */

  /** @type {Props & { [key: string]: any }} */
  let { ...props } = $props();
</script>

<div class={`md:px-8 px-5 -mx-5 md:-mx-8 py-2 pb-3 ${props.class}`}>
  {@render props.children?.()}
</div>
