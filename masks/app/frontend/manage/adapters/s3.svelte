<script>
let { change, adapter } = $props();
</script>

<div class="flex flex-col gap-1.5">
  <label class="input input-bordered input-sm flex items-center gap-3">
    <span class="opacity-75 text-xs min-w-[35px]">access key id</span>
    <input
      type="text"
      class="grow"
      value={adapter.config.accessKeyId}
      oninput={(e) => change({ accessKeyId: e.target.value })}
    />
  </label>

  <label class="input input-bordered input-sm flex items-center gap-3">
    <span class="opacity-75 text-xs min-w-[35px]">secret access key</span>
    <input
      type="text"
      class="grow"
      value={adapter.config.secretAccessKey}
      oninput={(e) => change({ secretAccessKey: e.target.value })}
    />
  </label>

  <label class="input input-bordered input-sm flex items-center gap-3">
    <span class="opacity-75 text-xs min-w-[35px]">region</span>
    <input
      type="text"
      class="grow"
      value={adapter.config.region}
      oninput={(e) => change({ region: e.target.value })}
    />
  </label>
  <label class="input input-bordered input-sm flex items-center gap-3">
    <span class="opacity-75 text-xs min-w-[35px]">bucket</span>
    <input
      type="text"
      class="grow"
      value={adapter.config.bucket}
      oninput={(e) => change({ bucket: e.target.value })}
    />
  </label>
</div>
