<script>
  let { icons, dark } = $props();
</script>

{#if dark}
  <div
    class="w-4 h-4 rounded shadow overflow-hidden flex text-center items-center bg-black p-[2px]"
  >
    <img src={icons?.dark} class="w-full h-full" alt="Security Key Icon" />
  </div>
{:else}
  <div
    class="w-4 h-4 rounded shadow overflow-hidden flex text-center items-center bg-white p-[2px]"
  >
    <img src={icons?.light} class="w-full h-full" alt="Security Key Icon" />
  </div>
{/if}
