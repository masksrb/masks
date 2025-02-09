<script>
  let { client, change, ...props } = $props();
</script>

<div class="flex flex-col gap-1.5">
  <div
    class="flex items-start gap-3 textarea textarea-bordered p-3 pb-2"
    data-theme="light"
  >
    <div class="w-20 h-20 rounded bg-white shadow" style={client.bgLight}></div>

    <div class="grow">
      <p class="text-xs opacity-75 mb-1.5">light background (css)</p>
      <textarea
        class="bg-transparent font-mono px-1.5 -ml-1 !outline-none w-full"
        value={client.bgLight}
        oninput={(e) => change({ bgLight: e.target.value })}
      ></textarea>
    </div>
  </div>

  <div
    class="flex items-start gap-3 textarea textarea-bordered p-3 pb-2 bg-black"
    data-theme="dark"
  >
    <div class="w-20 h-20 rounded bg-white shadow" style={client.bgDark}></div>

    <div class="grow">
      <p class="text-xs opacity-75 mb-1.5">dark background (css)</p>
      <textarea
        class="bg-transparent font-mono px-1.5 -ml-1 !outline-none w-full"
        value={client.bgDark}
        oninput={(e) => change({ bgDark: e.target.value })}
      ></textarea>
    </div>
  </div>
</div>
