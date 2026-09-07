<script>
let {
  login,
  busy = false,
  ready = true,
  label,
  working = null,
  quiet = false,
  plain = false,
  fit = false,
  grow = false,
  onclick = null,
  type = "button",
} = $props();

const held = $derived(busy || login.loading);
const shown = $derived(busy && working ? working : label);

const classes = $derived(
  [
    "action",
    quiet && "action-quiet",
    plain && "action-plain",
    fit && "action-fit",
    grow && "action-grow",
    busy && "action-busy",
  ]
    .filter(Boolean)
    .join(" "),
);
</script>

<button
  {type}
  {onclick}
  class={classes}
  disabled={!ready || held}
  aria-busy={busy || undefined}
>
  {#if busy}
    <span class="spinner action-mark"></span>
  {/if}
  {shown}
</button>
