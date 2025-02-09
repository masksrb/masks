<script>
  import { Phone, MessageSquare, Mail, Upload, ImageUp } from "lucide-svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import Alert from "@/components/Alert.svelte";
  let { change, settings } = $props();
</script>

<div class="flex flex-col gap-1.5">
  <div class="flex flex-col gap-1.5">
    <div class="flex items-center gap-2 mb-1.5">
      <p class="label-text-alt text-neutral-content opacity-75 truncate">
        Twilio settings — <i>Used for SMS-based verification...</i>
      </p>
    </div>

    <PasswordInput
      class="input-sm whitespace-nowrap"
      label="account sid"
      placeholder="..."
      value={settings.integration.twilio.accountSid}
      onChange={(e) =>
        change({ integration: { twilio: { accountSid: e.target.value } } })}
    />
    <PasswordInput
      class="input-sm whitespace-nowrap"
      label="auth token"
      placeholder="..."
      value={settings.integration.twilio.authToken}
      onChange={(e) =>
        change({ integration: { twilio: { authToken: e.target.value } } })}
    />
    <PasswordInput
      class="input-sm whitespace-nowrap"
      label="service sid"
      placeholder="..."
      value={settings.integration.twilio.serviceSid}
      onChange={(e) =>
        change({ integration: { twilio: { serviceSid: e.target.value } } })}
    />
  </div>
</div>
