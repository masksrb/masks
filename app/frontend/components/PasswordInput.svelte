<script>
  import { run, preventDefault, stopPropagation } from "svelte/legacy";

  import { Eye, EyeOff } from "lucide-svelte";

  let visible = $state(false);
  let toggle = () => {
    visible = !visible;
  };

  /**
   * @typedef {Object} Props
   * @property {any} value
   * @property {any} [label]
   * @property {any} disabled
   * @property {any} auth
   * @property {any} placeholder
   * @property {any} valid
   * @property {any} onChange
   * @property {import('svelte').Snippet} [before]
   * @property {import('svelte').Snippet} [right]
   * @property {import('svelte').Snippet} [end]
   */

  /** @type {Props} */
  let {
    value = $bindable(),
    label = null,
    disabled,
    auth,
    placeholder,
    valid = $bindable(),
    onChange,
    before,
    right,
    end,
    inputClass,
    class: cls,
    autofocus = false,
    ...props
  } = $props();

  let min = $state();
  let max = $state();
  let info = $state();

  $effect(() => {
    min = auth?.settings?.passwords?.minChars;
    max = auth?.settings?.passwords?.maxChars;

    if (!disabled && min && max) {
      valid = value && value.length >= min && value.length <= max;
      info = props.noinfo ? "" : `(${min} to ${max} characters)`;
    } else {
      valid = true;
    }
  });

  const SvelteComponent = $derived(visible ? EyeOff : Eye);
</script>

<label class={`input input-bordered flex items-center gap-3 ${cls}`}>
  {@render before?.()}

  {#if label}
    <span class="label-text-alt opacity-70 w-[70px]">{label}</span>
  {/if}

  {#if visible}
    <input
      {disabled}
      minlength={min}
      maxlength={max}
      type="text"
      placeholder={`${[placeholder, info].filter(Boolean).join(" ")}`}
      class={`placeholder:text-sm md:placeholder:text-base min-w-0 grow ${inputClass}`}
      bind:value
      oninput={onChange}
    />
  {:else}
    <input
      {disabled}
      minlength={min}
      maxlength={max}
      type="password"
      placeholder={`${[placeholder, info].filter(Boolean).join(" ")}`}
      class={`placeholder:text-sm md:placeholder:text-base min-w-0 grow ${inputClass}`}
      bind:value
      oninput={onChange}
      {autofocus}
    />
  {/if}

  {@render right?.()}

  <button onclick={stopPropagation(preventDefault(toggle))} type="button">
    <SvelteComponent size="16" />
  </button>

  {@render end?.()}
</label>
