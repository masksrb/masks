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
        Used for notifications and verification emails...
      </p>
    </div>

    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-text-alt truncate opacity-70 w-[70px]">from</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. mail@example.com..."
        value={settings.emails.from}
        oninput={(e) => change({ emails: { from: e.target.value } })}
      />
    </label>
    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-text-alt truncate opacity-70 w-[70px]">reply-to</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. no-reply@example.com..."
        value={settings.emails.replyTo}
        oninput={(e) => change({ emails: { replyTo: e.target.value } })}
      />
    </label>

    <div class="flex items-center gap-2 mt-3 mb-1.5">
      <p class="label-text-alt text-neutral-content opacity-75 truncate">
        SMTP settings
      </p>
    </div>
    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-text-alt truncate opacity-70 w-[70px]">address</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. smtp.example.com..."
        value={settings.integration.smtp.address}
        oninput={(e) =>
          change({ integration: { smtp: { address: e.target.value } } })}
      />
    </label>
    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-text-alt truncate opacity-70 w-[70px]">domain</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. example.com..."
        value={settings.integration.smtp.domain}
        oninput={(e) =>
          change({ integration: { smtp: { domain: e.target.value } } })}
      />
    </label>
    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-text-alt truncate opacity-70 w-[70px]">port</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. 25, 465 or 587..."
        value={settings.integration.smtp.port}
        oninput={(e) =>
          change({ integration: { smtp: { port: e.target.value } } })}
      />
    </label>
    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-text-alt truncate opacity-70 w-[70px]">username</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="..."
        value={settings.integration.smtp.userName}
        oninput={(e) =>
          change({ integration: { smtp: { userName: e.target.value } } })}
      />
    </label>
    <PasswordInput
      class="input-sm"
      label="password"
      placeholder="..."
      value={settings.integration.smtp.password}
      onChange={(e) =>
        change({ integration: { smtp: { password: e.target.value } } })}
    />
  </div>
</div>
