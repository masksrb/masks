<script>
  import { preventDefault, stopPropagation } from "svelte/legacy";

  import _ from "lodash-es";

  /**
   * @typedef {Object} Props
   * @property {any} loading
   * @property {any} disabled
   * @property {string} [label]
   */

  /** @type {Props} */
  let { loading, disabled, label = "go back", ...extras } = $props();
</script>

<button
  {...extras}
  type="button"
  class="btn btn-lg btn-error w-[130px] text-center"
  disabled={loading || disabled}
  onclick={stopPropagation(preventDefault(() => history.back()))}
>
  {#if loading}
    <span class="loading loading-spinner loading-md mx-auto"></span>
  {:else}
    {label}
  {/if}
</button>
