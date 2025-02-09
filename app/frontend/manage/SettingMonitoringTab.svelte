<script>
  import {
    Phone,
    MessageSquare,
    Mail,
    Upload,
    Info,
    ImageUp,
  } from "lucide-svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import Alert from "@/components/Alert.svelte";
  import CopyButton from "@/components/CopyButton.svelte";

  let { change, settings } = $props();
</script>

<Alert type="info" class="mb-3" icon={Info}>
  Managers can view and manage background jobs at <a
    class="underline font-mono whitespace-nowrap"
    href="/manage/jobs">/manage/jobs</a
  >.
</Alert>

<div class="flex flex-col gap-1.5">
  <div class="flex flex-col gap-1.5">
    <div class="flex items-center gap-2">
      <p class="label-text-alt text-neutral-content opacity-75 truncate">
        Sentry
      </p>
    </div>

    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-text-alt truncate opacity-70 w-[70px]">DSN</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. https://public@sentry.example.com/1..."
        value={settings.integration?.sentry?.dsn}
        oninput={(e) =>
          change({ integration: { sentry: { dsn: e.target.value } } })}
      />
    </label>

    <div class="flex items-center gap-2 mt-2">
      <p class="label-text-alt text-neutral-content opacity-75 truncate">
        New Relic
      </p>
    </div>

    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-text-alt truncate opacity-70 w-[70px]">App name</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. https://public@sentry.example.com/1..."
        value={settings.monitoringj?.newrelic?.app}
        oninput={(e) =>
          change({ monitoring: { newrelic: { app: e.target.value } } })}
      />
    </label>

    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-text-alt truncate opacity-70 w-[70px]"
        >License key</span
      >
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. https://public@sentry.example.com/1..."
        value={settings.monitoring?.newrelic?.licenseKey}
        oninput={(e) =>
          change({ monitoring: { newrelic: { licenseKey: e.target.value } } })}
      />
    </label>
  </div>
</div>
