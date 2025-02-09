<script>
  import { Phone, MessageSquare, Mail, Upload, ImageUp } from "lucide-svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import Alert from "@/components/Alert.svelte";

  let { adapter, change, settings } = $props();
</script>

<div class="flex flex-col gap-1.5">
  <div class="flex flex-col gap-1.5">
    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-xs truncate opacity-70 w-[70px]">location</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. /usr/sbin/sendmail"
        value={adapter.config.location}
        oninput={(e) => change({ location: e.target.value })}
      />
    </label>
    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-xs truncate opacity-70 w-[70px]">arguments</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. -i"
        value={adapter.config.arguments}
        oninput={(e) => change({ arguments: e.target.value })}
      />
    </label>
  </div>
</div>
