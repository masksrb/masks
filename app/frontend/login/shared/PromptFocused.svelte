<script>
  import Identicon from "@/components/Identicon.svelte";

  let { auth, children } = $props();
</script>

<div class="py-6">
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
  {/if}

  <div class="rows-3 px-3 md:px-6">
    {@render children()}
  </div>
</div>
