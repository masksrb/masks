<script>
  /**
   * @typedef {Object} Props
   * @property {string} [type]
   * @property {any} [icon]
   * @property {import('svelte').Snippet} [children]
   */

  /** @type {Props} */
  let { type = "info", icon = null, children, class: cls, ...props } = $props();

  let classes = {
    info: [
      `dark:bg-sky-950 dark:border-sky-900 dark:text-sky-200`,
      `bg-sky-50 border-sky-200 text-sky-800`,
    ],
    neutral: ["bg-neutral text-neutral-content border-neutral"],
    secondary: [
      `dark:bg-purple-950 dark:border-purple-900 dark:text-purple-200`,
      `bg-purple-50 border-purple-100 text-purple-800`,
    ],
    gray: [
      `dark:bg-gray-950 dark:border-gray-900 dark:text-gray-300`,
      `bg-gray-400 border-gray-400 text-gray-700`,
    ],
    success: [
      `dark:bg-green-950 dark:border-green-900 dark:text-green-200`,
      `bg-green-50 border-green-200 text-green-800`,
    ],
    warn: [
      `dark:bg-yellow-950 dark:border-yellow-900 dark:text-yellow-200`,
      `bg-yellow-50 border-yellow-100 text-yellow-800`,
    ],
    error: [
      `dark:bg-red-950 dark:border-red-900 dark:text-red-200`,
      `bg-red-50 border-red-100 text-red-800`,
    ],
    primary: [
      `dark:bg-indigo-950 dark:border-indigo-900 dark:text-indigo-200`,
      `bg-indigo-50 border-indigo-100 text-indigo-800`,
    ],
    accent: [
      `dark:bg-teal-950 dark:border-teal-900 dark:text-teal-200`,
      `bg-teal-50 border-teal-100 text-teal-800`,
    ],
    emerald: [
      `dark:bg-emerald-950 dark:border-emerald-900 dark:text-emerald-200`,
      `bg-emerald-50 border-emerald-100 text-emerald-800`,
    ],
    webauthn: [
      `dark:bg-webauthn-950 dark:border-webauthn-900 dark:text-webauthn-200`,
      `bg-webauthn-50 border-webauthn-100 text-webauthn-800`,
    ],
  };
</script>

<div
  class="
 dark:bg-webauthn-950 dark:border-webauthn-900 dark:text-webauthn-200
 bg-webauthn-50 border-webauthn-100 text-webauthn-800
"
></div>

<div
  class={[
    "px-3 py-3 border rounded-lg",
    "shadow flex items-start gap-3 text-left md:text-base text-sm",
    cls,
    ...(classes[type] || []),
  ].join(" ")}
>
  {#if children}
    <p class="md:mx-1 mx-0.5 grow w-full">
      {@render children?.()}
    </p>
  {:else if props.errors?.length}
    <ul class="grow">
      {#each props.errors as error}
        <li>{error}</li>
      {/each}
    </ul>
  {/if}

  {#if icon}
    {@const SvelteComponent = icon}
    <div class="">
      <SvelteComponent />
    </div>
  {/if}
</div>
