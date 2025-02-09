<script>
  import { Phone, MessageSquare, Mail, Upload, ImageUp } from "lucide-svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import Alert from "@/components/Alert.svelte";
  let { change, adapter } = $props();
</script>

<div class="flex flex-col gap-1.5">
  <div class="flex flex-col gap-1.5">
    <div class="flex items-center gap-2 mb-1.5">
      <p class="label-text-alt text-neutral-content opacity-75 truncate">
        <i>Used for SMS-based verification...</i>
      </p>
    </div>

    <PasswordInput
      class="input-sm whitespace-nowrap"
      label="account sid"
      placeholder="..."
      value={adapter.config.accountSid}
      onChange={(e) => change({ accountSid: e.target.value })}
    />
    <PasswordInput
      class="input-sm whitespace-nowrap"
      label="auth token"
      placeholder="..."
      value={adapter.config.authToken}
      onChange={(e) => change({ authToken: e.target.value })}
    />
    <PasswordInput
      class="input-sm whitespace-nowrap"
      label="service sid"
      placeholder="..."
      value={adapter.config.serviceSid}
      onChange={(e) => change({ serviceSid: e.target.value })}
    />
  </div>
</div>
