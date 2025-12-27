<script>
let props = $props();
let visible = $state();

let showCode = (type) => {
  visible = type === visible ? null : type;
};
</script>

<div class="rounded-lg bg-gray-100 dark:bg-gray-950 p-3 px-4">
  {#each Object.entries(props.types) as [type, conf]}
    <div class="flex flex-col">
      <div class="flex items-center gap-3">
        <span class="font-mono font-bold">{type}</span>
        <span class="opacity-75 grow truncate text-sm">{conf.desc}</span>
        <button
          class="underline cursor-pointer !font-bold text-left"
          type="button"
          onclick={() => showCode(type)}
          ><span class="text-sm">{visible == type ? "hide" : "defaults"}</span
          ></button
        >
      </div>

      {#if visible == type}
        <pre
          class="w-full rounded p-3 bg-gray-900 text-green-200">{conf.json}</pre>
      {/if}
    </div>
  {/each}
</div>
