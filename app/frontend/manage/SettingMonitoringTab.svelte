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
  import { getContext } from "svelte";

  let { change, settings } = $props();
  let { root } = getContext("page");
</script>

<Alert type="info" class="mb-3" icon={Info}>
  Managers can view and manage background jobs at <a
    class="underline font-mono whitespace-nowrap"
    href={`${root}/jobs`}>{`${root}/jobs`}</a
  >.
</Alert>

<div class="flex flex-col gap-1.5">
  <div class="flex flex-col gap-1.5">
    <div class="flex items-center gap-2">
      <p class="label-xs text-neutral-content opacity-75 truncate">Sentry</p>
    </div>

    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-xs truncate opacity-70 w-[70px]">DSN</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. https://public@sentry.example.com/1..."
        value={settings.sentryDsn}
        oninput={(e) => change({ sentryDsn: e.target.value })}
      />
    </label>

    <div class="flex items-center gap-2 mt-2">
      <p class="label-xs text-neutral-content opacity-75 truncate">New Relic</p>
    </div>

    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-xs truncate opacity-70 w-[70px]">App name</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="..."
        value={settings.newrelicApp}
        oninput={(e) => change({ newrelicApp: e.target.value })}
      />
    </label>

    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-xs truncate opacity-70 w-[70px]">License key</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="..."
        value={settings.newrelicLicenseKey}
        oninput={(e) => change({ newrelicLicenseKey: e.target.value })}
      />
    </label>
  </div>
</div>
