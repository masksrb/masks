<script>
  import _ from "lodash-es";
  import { onMount } from "svelte";
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
  import {
    mutationStore,
    queryStore,
    gql,
    getContextClient,
  } from "@urql/svelte";

  let { error, ...props } = $props();

  let modal;
  let showModal = () => {
    modal.showModal();
  };

  onMount(() => {
    showModal();
  });
</script>

<dialog class="modal bg-gray-900" bind:this={modal}>
  <div class="modal-box bg-gray-950 p-10 shadow-2xl">
    <h3 class="text-4xl text-error font-bold mb-6">An error occurred...</h3>
    <p class="text-xl">
      You can ignore the error or <button
        class="underline"
        onclick={() => window.location.reload()}>refresh the page</button
      > to continue.
    </p>
    <div class="block bg-black p-3 font-mono rounded text-green-200 my-3">
      {error}
    </div>
    <div class="modal-action">
      <form method="dialog">
        <button class="btn">Close</button>
      </form>
    </div>
  </div>
</dialog>
