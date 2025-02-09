<script>
  import Time from "../components/Time.svelte";
  import Identicon from "@/components/Identicon.svelte";
  import EditableImage from "@/components/EditableImage.svelte";
  import { Save, ChevronRight, X } from "lucide-svelte";
  import CopyText from "@/components/CopyText.svelte";

  /**
   * @typedef {Object} Props
   * @property {any} actor
   */

  /** @type {Props} */
  let { actor, editable = false, ...props } = $props();

  let form = { ...actor };
</script>

<div
  class={`h-[74px] grow flex items-center gap-3  px-3 rounded-lg ${props.class}`}
>
  <div class="w-14 h-14">
    <EditableImage
      disabled={props.disabled}
      endpoint="/upload/avatar"
      params={{ actor_id: actor.id }}
      src={actor?.avatar}
      class="w-14 h-14"
    />
  </div>

  <div class="grow flex flex-col truncate px-1.5">
    <div class="font-bold text-xl text-white text-black truncate mb-0.5">
      {actor.name || actor.identifier}
    </div>

    <CopyText label="id" text={actor.id} />
  </div>

  <div class="flex flex-col items-end gap-1.5">
    <div class="min-w-6 w-6 h-6 bg-black rounded">
      <Identicon id={actor.identiconId} />
    </div>

    <div class="flex items-center gap-1.5">
      {#if props.isCurrent}
        <div class="text-xs italic font-bold text-info">you</div>
      {/if}

      <div class="text-xs whitespace-nowrap">
        last login

        <span class="italic">
          {#if actor.lastLoginAt}
            <Time relative timestamp={actor.lastLoginAt} />
          {:else}
            never
          {/if}
        </span>
      </div>
    </div>
  </div>
</div>
