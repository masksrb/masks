<script>
  import Identicon from "@/components/Identicon.svelte";
  let { actor } = $props();
</script>

<div class="avatar placeholder w-full h-full">
  <div class="bg-black text-neutral-content p-0.5 rounded-lg">
    <Identicon id={actor?.identiconId} />
  </div>
</div>
