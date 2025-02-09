<script>
  import {
    ServerCog,
    SquarePen,
    SquarePower,
    RotateCcw,
    PlusSquare,
    Cog,
    ListCheck,
    UserPlus,
    User,
    Handshake,
    KeySquare,
    X,
    Plus,
    Search,
    ChevronLeft,
  } from "lucide-svelte";

  import AddActor from "./AddActor.svelte";
  import AddClient from "./AddClient.svelte";
  import AddToken from "./AddToken.svelte";

  let { oncancel } = $props();
  let adding = $state();
  let types = {
    actor: {
      name: "Actor",
      icon: User,
      component: AddActor,
    },
    client: {
      name: "Client",
      icon: Handshake,
      component: AddClient,
    },
    token: {
      name: "Token",
      icon: KeySquare,
      component: AddToken,
    },
  };

  let add = (type) => {
    return () => {
      adding = type;
    };
  };

  let modal;
  let isOpen = $state();
  let showModal = () => {
    modal.showModal();
  };

  let hideModal = () => {
    modal.close();
  };
</script>

<button
  tabindex="0"
  onclick={showModal}
  class={`btn btn-sm px-0 w-8 py-0 btn-ghost`}
>
  <PlusSquare size="20" />
</button>

<dialog
  id="add-model"
  class="modal modal-top bg-gray-950 bg-opacity-50"
  bind:this={modal}
>
  <div
    class="modal-box bg-gray-950 bg-opacity-100 w-full max-w-prose mx-auto rounded-b-lg"
  >
    <div class="flex items-center gap-3 mb-6">
      <h1 class="text-3xl text-white font-bold grow">Add a new...</h1>
      <button onclick={hideModal} class="btn btn-link text-neutral"
        ><X size="30" /></button
      >
    </div>
    <div
      class="flex items-center gap-3 flex-grow justify-between [&>button]:h-auto [&>button]:py-6 [&>button]:text-xl"
    >
      {#each Object.entries(types) as [key, data]}
        {@const Icon = data.icon}
        <button
          class={`btn btn-xl grow btn-outline flex flex-col md:flex-row ${adding == key ? "btn-primary" : !adding ? "" : "opacity-75"}`}
          onclick={add(key)}
        >
          <Icon />
          {data.name}
        </button>
      {/each}
    </div>

    {#if adding}
      {@const Component = types[adding].component}
      <div class="mt-6 w-full">
        <Component />
      </div>
    {/if}
  </div>
</dialog>
