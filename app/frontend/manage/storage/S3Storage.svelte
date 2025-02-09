<script>
  let { change, settings } = $props();
</script>

<div class="flex flex-col gap-1.5">
  <label class="input input-bordered input-sm flex items-center gap-3">
    <span class="opacity-75 text-xs min-w-[35px]">access key id</span>
    <input
      type="text"
      class="grow"
      value={settings.integration.s3.accessKeyId}
      oninput={(e) =>
        change({ integration: { s3: { accessKeyId: e.target.value } } })}
    />
  </label>

  <label class="input input-bordered input-sm flex items-center gap-3">
    <span class="opacity-75 text-xs min-w-[35px]">secret access key</span>
    <input
      type="text"
      class="grow"
      value={settings.integration.s3.secretAccessKey}
      oninput={(e) =>
        change({ integration: { s3: { secretAccessKey: e.target.value } } })}
    />
  </label>

  <label class="input input-bordered input-sm flex items-center gap-3">
    <span class="opacity-75 text-xs min-w-[35px]">region</span>
    <input
      type="text"
      class="grow"
      value={settings.integration.s3.region}
      oninput={(e) =>
        change({ integration: { s3: { region: e.target.value } } })}
    />
  </label>
  <label class="input input-bordered input-sm flex items-center gap-3">
    <span class="opacity-75 text-xs min-w-[35px]">bucket</span>
    <input
      type="text"
      class="grow"
      value={settings.integration.s3.bucket}
      oninput={(e) =>
        change({ integration: { s3: { bucket: e.target.value } } })}
    />
  </label>
</div>
