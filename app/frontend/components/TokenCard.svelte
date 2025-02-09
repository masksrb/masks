<script>
  import { Save, ChevronDown, X } from "lucide-svelte";
  import Time from "svelte-time";

  let { token } = $props();

  let form = { ...token };
</script>

<div class="my-1.5 bg-base-200 rounded-lg p-3 px-3">
  <div class="flex items-center pl-1.5 gap-3"></div>
</div>
