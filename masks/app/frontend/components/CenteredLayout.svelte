<script>
import _ from "lodash-es";
import { Info } from "lucide-svelte";
import { toasts } from "@/lib/toast";
import { setContext } from "svelte";

let props = $props();

let innerWidth = $state();
let autofocus = $derived(innerWidth > 768);

$effect(() => {
  setContext("autofocus", autofocus);
});
</script>

<svelte:window bind:innerWidth />

<div
  class="background animate-fade-in flex flex-col min-h-full md:p-3 px-[5px] items-center justify-center"
>
  <div class="w-full md:w-[500px] mx-auto rounded-b-2xl shadow-2xl">
    <div
      class={`bg-white dark:bg-black !bg-opacity-90 h-[25px] md:h-[32px] rounded-2xl w-full relative border-t border-white dark:border-opacity-20 border-opacity-50`}
    ></div>
    <div class="w-full md:w-[500px] mx-auto relative rounded-2xl shadow-xl">
      {@render props.children?.()}
    </div>
  </div>
</div>

{#if $toasts.length}
  <div
    class={`w-full fixed left-0 right-0 bottom-0 p-6 md:p-12 animate-fade-in`}
  >
    <div class="max-w-[500px] mx-auto">
      <div
        class={[
          "box bg-accent",
          "shadow-2xl cols-3 text-accent-content text-xl rounded-full font-bold",
        ].join(" ")}
      >
        <Info size="25" class="ml-1 dim" />

        {$toasts[0]}
      </div>
    </div>
  </div>
{/if}
