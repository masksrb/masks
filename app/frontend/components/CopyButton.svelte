<script>
  import { copy } from "svelte-copy";
  import {
    ClipboardX,
    ClipboardCheck,
    ClipboardCopy,
    LogOut,
    RotateCcw,
    MailPlus,
    Trash2 as Trash,
    User,
  } from "lucide-svelte";

  let { ...props } = $props();
  let copied = $state(false);
  let copyError = $state(false);
  let timeout = $state();
  let onCopy = () => {
    copied = true;

    clearTimeout(timeout);
    timeout = setTimeout(() => {
      copied = false;
    }, 2000);
  };
  let onCopyError = () => {
    copyError = true;
    copied = false;

    clearTimeout(timeout);
    timeout = setTimeout(() => {
      copyError = false;
    }, 2000);
  };
</script>

<button
  class={`${props.class} ${
    copied ? "text-success" : copyError ? "text-error" : ""
  }`}
  use:copy={{ text: props.value, onCopy, onError: onCopyError }}
>
  <span>
    {#if copied}
      <ClipboardCheck size="14" />
    {:else if copyError}
      <ClipboardX size="14" />
    {:else}
      <ClipboardCopy size="14" />
    {/if}
  </span>

  {@render props?.after?.({ copied })}
</button>
