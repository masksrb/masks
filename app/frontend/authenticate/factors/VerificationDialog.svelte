<script>
  import _ from "lodash-es";
  import { X } from "lucide-svelte";

  import Dialog from "@/components/Dialog.svelte";
  import Verification from "./Verification.svelte";

  import { onMount } from "svelte";

  let props = $props();

  let close = (e) => {
    props.onclose?.(e);
  };

  let visible = $state();

  onMount(() => {
    let verify = true;

    if (props.prompt.verifying.if) {
      verify = props.prompt.verifying.if(props.prompt);
    }

    if (verify) {
      visible = true;
    } else {
      props.authorize({ sudo: true });
    }
  });
</script>

{#if visible}
  <Dialog onclose={close}>
    <Verification {...props}>
      {#snippet cancel()}
        <form method="dialog" class="cols-3 justify-center">
          <button
            class="btn btn-sm btn-neutral btn-ghost btn-square"
            onclick={close}><X size="30" /></button
          >
        </form>
      {/snippet}
    </Verification>
  </Dialog>
{/if}
