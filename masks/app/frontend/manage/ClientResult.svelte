<script>
import { run } from "svelte/legacy";

import _ from "lodash-es";
import Time from "@/components/Time.svelte";
import CopyButton from "@/components/CopyButton.svelte";
import EditableImage from "@/components/EditableImage.svelte";
import { getContext } from "svelte";

/**
 * @typedef {Object} Props
 * @property {any} client
 * @property {boolean} [editing]
 * @property {any} [isEditing]
 */

/** @type {Props} */
let { client, ...props } = $props();
let { root } = getContext("page");
</script>

<div
  class={`h-[74px] w-full rounded-lg p-1 pl-3 relative overflow-hidden
  ${props.class}`}
>
  <div class="z-10 flex items-center relative">
    <div class="w-14 h-14 min-w-14 min-h-14">
      <EditableImage
        disabled={props.disabled}
        endpoint={`${root}/upload/client`}
        params={{ client_id: client.id }}
        src={client.logo}
        class="w-14 h-14"
      />
    </div>

    <div class="w-full max-w-full overflow-auto p-1.5 grow">
      <div class="flex flex-col">
        {#if props.disabled}
          <span
            class="bg-transparent font-bold text-xl pl-1 w-full min-w-0 p-0
          pb-1.5 !outline-none text-black dark:text-white">{client.name}</span
          >
        {:else}
          <input
            type="text"
            value={client.name}
            oninput={(e) => props.change?.({ name: e.target.value })}
            class="input input-ghost font-bold input-sm text-xl pl-1 w-full min-w-0 py-1.5 pb-2 !outline-none text-black dark:text-white"
          />
        {/if}

        <div class="flex items-center gap-3 pl-0.5">
          <span
            class="label-xs whitespace-nowrap bg-base-100
            p-0.5 rounded px-1.5 bg-opacity-25"
          >
            <Time timestamp={client.createdAt} ago="old" />.
          </span>

          {#if props.disabled}
            <span
              class="flex items-center gap-1.5 grow !bg-transparent truncate
              text-neutral dark:text-base-content text-sm"
            >
              <span class="text-neutral dark:text-base-content opacity-75">
                id
              </span>

              {client.id}
            </span>
          {:else}
            <label class="cols grow text-xs gap-1">
              <CopyButton value={client.id} />

              <span class="text-neutral dark:text-base-content label-xs">
                id
              </span>

              <span class="text-neutral dark:text-base-content">
                {client.id}
              </span>
            </label>
          {/if}
        </div>
      </div>
    </div>

    {@render props.after?.()}
  </div>
</div>
