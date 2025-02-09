<script>
  import Icon from "@iconify/svelte";
  import PromptIdentifier from "./PromptIdentifier.svelte";
  import { iconifyProvider } from "@/lib";

  let { auth, heading, provider, ...props } = $props();
</script>

<div class="justify-center flex">
  <div
    class="bg-base-100 rounded-full shadow-inner mb-3 dark:fill-white fill-black w-full mx-10 max-w-[200px] max-h-[200px]"
  >
    <Icon
      icon={iconifyProvider(provider)}
      width="100%"
      height="100%"
      class="p-[10%] border-box"
    />
  </div>
</div>

<div class="flex items-center gap-6 justify-center pt-6 pb-1.5">
  <div class="text-2xl">
    {@render heading()}
  </div>
</div>

{@render props.alert?.()}

{#if auth?.actor && auth?.trusted}
  <div class="my-3">
    <PromptIdentifier {auth} />
  </div>
{/if}
