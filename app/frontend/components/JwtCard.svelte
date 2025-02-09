<script>
  import { preventDefault, stopPropagation } from "svelte/legacy";

  import { Save, ChevronDown, X } from "lucide-svelte";
  import Time from "svelte-time";

  let { event, search } = $props();

  let form = { ...event };
</script>

<div class="my-1.5 bg-base-200 rounded-lg p-3 px-3">
  <div class="flex items-center pl-1.5 gap-3">
    <h2 class="font-bold font-mono">{event.name}</h2>
    <button
      onclick={stopPropagation(preventDefault(search(event.clientId)))}
      class="btn btn-link underline">{event.clientId}</button
    >
    <span class="text-sm" alt={event.device.userAgent}
      >{event.device.name} on {event.device.os}</span
    >
    <span class="text-sm font-mono">{event.device.ipAddress}</span>
    <span class="italic"><Time relative timestamp={event.createdAt} /></span>
  </div>
</div>
