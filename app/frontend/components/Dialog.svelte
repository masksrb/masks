<script>
  import { onMount } from "svelte";

  let { open = $bindable(), ...props } = $props();

  let modal;

  onMount(() => {
    showModal();
  });

  let close = (event) => {
    props.onclose?.(event);
    modal.close();
  };

  let showModal = () => {
    modal.showModal();
    modal.addEventListener("close", close);
  };
</script>

<dialog
  class="modal bg-neutral dark:bg-gray-950 !bg-opacity-65 p-1.5 backdrop-blur animate-fade-in-fast"
  bind:this={modal}
>
  <div
    class="modal-box dark:bg-black bg-white p-6 md:p-10 shadow-2xl min-h-[300px] w-full relative overflow-y-visible border-t border-neutral border-opacity-50"
  >
    {@render props.children?.({ close })}
  </div>
</dialog>
