<script>
  let { settings } = $props();
</script>

<label class="input input-bordered input-sm flex items-center gap-3">
  <span class="opacity-75 text-xs min-w-[35px]">directory</span>
  <input
    type="text"
    class="grow"
    value={settings.integration.disk.root}
    oninput={(e) => change({ integration: { disk: { root: e.target.value } } })}
  />
</label>
