<script>
import Identicon from "@/components/Identicon.svelte";

let { auth, children, ...props } = $props();
</script>

<div class="pb-6">
  {#if auth?.actor}
    <div class="mb-6">
      <div
        class="mx-auto text-center w-[150px] h-[150px] dark:bg-base-300 bg-black rounded-lg shadow-xl"
      >
        {#if auth?.actor?.avatar}
          <img src={auth.actor.avatar} class="object-cover" alt="avatar" />
        {:else}
          <Identicon id={auth.actor.identiconId} />
        {/if}
      </div>

      <div class="dim text-xl text-center pt-1.5 font-bold">
        {auth?.actor?.identifier}
      </div>
    </div>
  {:else if props.icon || props.title}
    {@const Icon = props.icon}

    <div class="mb-6">
      {#if props.icon}
        <div class="mb-3 mx-auto text-center cols justify-center">
          <Icon size="50" class={props.iconClass} />
        </div>
      {/if}

      <div class="text-3xl text-center pt-1.5 font-bold">
        {props.title}
      </div>
    </div>
  {/if}

  <div class="rows-3 px-3 md:px-6">
    {@render children()}
  </div>
</div>
