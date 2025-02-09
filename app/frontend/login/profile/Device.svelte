<script>
  import DeviceIcon from "@/components/DeviceIcon.svelte";
  import Time from "@/components/Time.svelte";

  let { device } = $props();
</script>

<span class={"block mb-1.5 bg-base-100 rounded-lg p-3 py-1.5"}>
  <span class="flex items-center gap-3 text-sm w-full">
    <span class="px-1.5">
      <DeviceIcon {device} size="14" />
    </span>

    <span class="whitespace-nowrap font-bold" alt={device.userAgent}
      >{device.name} on {device.os}</span
    >
    <span class="text-xs font-mono grow">{device.ip}</span>

    <span class="whitespace-nowrap text-xs opacity-75"
      ><Time relative timestamp={device.createdAt} ago="old" /></span
    >
  </span>
</span>
