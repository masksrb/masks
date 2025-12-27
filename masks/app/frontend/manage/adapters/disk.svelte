<script>
let { change, adapter } = $props();
</script>

<label class="input input-bordered input-sm flex items-center gap-3">
  <span class="opacity-75 text-xs min-w-[35px]">directory</span>
  <input
    type="text"
    class="grow"
    value={adapter.config.root}
    oninput={(e) => change({ root: e.target.value })}
  />
</label>
