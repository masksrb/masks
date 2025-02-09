<script>
  let { client, change, ...props } = $props();
</script>

<div class="flex flex-col gap-1.5">
  <p class="text-xs opacity-75 text-neutral-content">
    custom <span class="font-mono">css</span>
  </p>
  <div class="textarea textarea-bordered p-3 pb-2 mb-1.5">
    <textarea
      class="bg-transparent font-mono px-1.5 -ml-1 !outline-none w-full min-h-[300px]"
      value={client.styles}
      oninput={(e) => change({ styles: e.target.value })}
    ></textarea>
  </div>
</div>
