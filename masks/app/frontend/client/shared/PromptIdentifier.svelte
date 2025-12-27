<script>
import { preventDefault, stopPropagation } from "svelte/legacy";

import Identicon from "@/components/Identicon.svelte";
import { Lock, ImageOff, RotateCcw } from "lucide-svelte";

let { children, auth, startOver, avatarOnly, alternate, class: cls } = $props();

let avatar = $derived(auth.actor?.avatar);
let identifier = $derived(auth.actor?.identifier);
let identiconId = $derived(auth.actor?.identiconId);
</script>

{#if identifier}
  <div
    class={[
      "flex items-center gap-3 bg-base-100  rounded-lg font-bold border dark:border-neutral border-neutral-content",
      avatarOnly ? "" : "py-2 pl-3",
      cls,
    ].join(" ")}
  >
    <button
      type="button"
      class={[
        "avatar outline-none relative",
        startOver ? "cursor-pointer" : "",
      ].join(" ")}
      onclick={startOver}
    >
      <div class={`w-10 rounded bg-black my-1 group`}>
        <div class={startOver ? "group-hover:hidden" : ""}>
          {#if avatar}
            <img src={avatar} class="object-cover" alt="avatar" />
          {:else if identiconId}
            {#key identiconId}
              <Identicon id={identiconId} />
            {/key}
          {:else}
            <div class="w-full h-10 flex items-center justify-center">
              <ImageOff size="18" class="opacity-75" />
            </div>
          {/if}
        </div>

        {#if startOver}
          <div
            class="group-hover:absolute bg-black flex items-center justify-center left-0 right-0 top-0 bottom-0 m-1 rounded-lg"
          >
            <RotateCcw />
          </div>
        {/if}
      </div>
    </button>

    {#if !avatarOnly}
      <div class="grow overflow-hidden">
        <div class="text-xl truncate">
          {identifier}
        </div>

        {#if alternate}
          <div class="font-normal truncate">
            {alternate}
          </div>
        {/if}
      </div>

      {#if startOver}
        <div class="mr-1.5">
          <button
            type="button"
            class="btn btn-ghost"
            onclick={stopPropagation(preventDefault(startOver))}
            ><RotateCcw size="22" /></button
          >
        </div>
      {:else if auth?.trusted}
        <div class="mr-6 text-accent">
          <Lock />
        </div>
      {/if}
    {/if}

    {@render children?.()}
  </div>
{:else}
  <div
    class={[
      "flex items-center gap-3 bg-neutral text-neutral-content shadow font-bold opacity-70",
      "rounded-lg shadow",
      avatarOnly ? "" : "py-2 px-3",
      cls,
    ].join(" ")}
  >
    <div class={["avatar relative"].join(" ")}>
      <div
        class={`${avatarOnly ? "w-14" : "w-12"} rounded-lg bg-base-300 m-1 group`}
      ></div>
    </div>

    {#if !avatarOnly}
      <div class="text-xl grow mr-3">
        <div class="skeleton rounded-lg h-10 w-1/2"></div>
      </div>
    {/if}
  </div>
{/if}
