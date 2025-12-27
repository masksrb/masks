<script>
import PromptHeader from "../shared/PromptHeader.svelte";

let props = $props();
</script>

<div class="rows-1.5 items-center justify-center">
  <div class="dark:text-white text-black text-[50px] font-bold">masks</div>
  <div class="text-[20px] font-mono mb-6">v{props.backend.version}</div>
  <div class="text-[25px] text-center px-3 text-2xl">
    Masks is not installed.
  </div>
</div>
