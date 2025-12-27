<script>
import { Phone, MessageSquare, Mail, Upload, ImageUp } from "lucide-svelte";
import PasswordInput from "@/components/PasswordInput.svelte";
import Alert from "@/components/Alert.svelte";

let { adapter, change, settings } = $props();
</script>

<div class="flex flex-col gap-1.5">
  <div class="flex flex-col gap-1.5">
    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-xs truncate opacity-70 w-[70px]">address</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. smtp.example.com..."
        value={adapter.config.address}
        oninput={(e) => change({ address: e.target.value })}
      />
    </label>
    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-xs truncate opacity-70 w-[70px]">domain</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. example.com..."
        value={adapter.config.domain}
        oninput={(e) => change({ domain: e.target.value })}
      />
    </label>
    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-xs truncate opacity-70 w-[70px]">port</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. 25, 465 or 587..."
        value={adapter.config.port}
        oninput={(e) => change({ port: e.target.value })}
      />
    </label>
    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-xs truncate opacity-70 w-[70px]">username</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="..."
        value={adapter.config.userName}
        oninput={(e) => change({ userName: e.target.value })}
      />
    </label>
    <PasswordInput
      class="input-sm"
      label="password"
      placeholder="..."
      value={adapter.config.password}
      onChange={(e) => change({ password: e.target.value })}
    />
  </div>
</div>
