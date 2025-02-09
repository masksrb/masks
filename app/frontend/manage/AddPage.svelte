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
    Ticket,
    Theater,
    X,
    Plus,
    Search,
    ChevronLeft,
    Globe,
    Tickets,
    TicketPlus,
    DoorOpen,
  } from "lucide-svelte";

  import AddActor from "./AddActor.svelte";
  import AddClient from "./AddClient.svelte";
  import AddToken from "./AddToken.svelte";
  import AddProvider from "./AddProvider.svelte";

  let adding = $state();
  let types = {
    actor: {
      name: "Actor",
      icon: User,
      component: AddActor,
      active: "btn-error",
    },
    client: {
      name: "Client",
      icon: DoorOpen,
      component: AddClient,
      active: "btn-secondary",
    },
    provider: {
      name: "Provider",
      icon: Handshake,
      component: AddProvider,
      active: "btn-primary",
    },
    token: {
      name: "Token",
      icon: TicketPlus,
      component: AddToken,
      active: "btn-accent",
    },
  };

  let add = (type) => {
    return () => {
      adding = type;
    };
  };

  let modal;
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
      <button onclick={hideModal} class="btn btn-link text-neutral-content"
        ><X size="30" /></button
      >
    </div>
    <div
      class="flex items-center gap-3 flex-grow justify-between [&>button]:h-auto [&>button]:py-3 [&>button]:md:text-lg"
    >
      {#each Object.entries(types) as [key, data]}
        {@const Icon = data.icon}
        <button
          class={`btn btn-lg grow btn-outline flex flex-col ${adding == key ? data.active : !adding ? "" : "opacity-75"}`}
          onclick={add(key)}
        >
          <Icon />

          <span class="text-xs md:text-lg">
            {data.name}
          </span>
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
