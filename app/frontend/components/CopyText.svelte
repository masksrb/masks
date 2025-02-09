<script>
  import CopyButton from "./CopyButton.svelte";

  let { ...props } = $props();
</script>

<label
  class="!cursor-pointer input input-xs border-none min-w-0 !bg-transparent w-full px-0 !outline-none flex items-center gap-1.5"
>
  <CopyButton value={props.text} />

  <span
    class={`text-base-content opacity-75 whitespace-nowrap ${props.labelClass}`}
  >
    {props.label}
  </span>

  <input
    type="text"
    value={props.text}
    disabled
    class="cursor-pointer min-w-0 w-full text-base-content !outline-none"
  />
</label>
