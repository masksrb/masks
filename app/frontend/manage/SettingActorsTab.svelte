<script>
  import Alert from "@/components/Alert.svelte";
  import { UserX, Trash, CalendarX2 } from "lucide-svelte";
  import ProvidersEditor from "./ProvidersEditor.svelte";

  let { settings, change, loading, errors, save, ...props } = $props();
</script>

<div class="flex flex-col gap-1.5">
  <div class="mb-3">
    <ProvidersEditor {settings} />
  </div>

  <div class="mb-1.5 pl-1.5">
    <p class="label-text-alt text-neutral-content opacity-75">Credentials</p>
  </div>

  <div class="bg-base-200 rounded-lg px-4 py-3">
    <div class="flex items-center gap-3 text-xs">
      <span class="text-sm grow">Nicknames</span>
      <span class="text-xs truncate opacity-75">characters</span>
      <label class="flex items-center gap-3">
        <input
          type="text"
          placeholder="..."
          class="input input-xs max-w-[60px]"
          value={settings.nicknames.minChars}
          oninput={(e) => change({ nicknames: { minChars: e.target.value } })}
        />
        <span class="opacity-75">min</span>
      </label>
      <label class="flex items-center gap-3">
        <input
          type="text"
          placeholder="..."
          class="input input-xs max-w-[60px]"
          value={settings.nicknames.maxChars}
          oninput={(e) => change({ nicknames: { maxChars: e.target.value } })}
        />

        <span class="opacity-75">max</span>
      </label>
    </div>
    <div class="flex items-center gap-3 text-xs mt-1.5">
      <span class="text-xs opacity-75">format</span>
      <label class="flex items-center gap-3 grow">
        <input
          type="text"
          placeholder="..."
          class="input input-xs w-full grow font-mono"
          value={settings.nicknames.format}
          oninput={(e) => change({ backupCodes: { total: e.target.value } })}
        />
      </label>
    </div>
  </div>

  <div class="bg-base-200 rounded-lg px-4 py-3">
    <div class="flex items-center gap-3 text-xs">
      <span class="text-sm grow">Passwords</span>
      <span class="text-xs truncate opacity-75">characters</span>
      <label class="flex items-center gap-3">
        <input
          type="text"
          placeholder="..."
          class="input input-xs max-w-[60px]"
          value={settings.passwords.minChars}
          oninput={(e) => change({ passwords: { minChars: e.target.value } })}
        />
        <span class="opacity-75">min</span>
      </label>
      <label class="flex items-center gap-3">
        <input
          type="text"
          placeholder="..."
          class="input input-xs max-w-[60px]"
          value={settings.passwords.maxChars}
          oninput={(e) => change({ passwords: { maxChars: e.target.value } })}
        />

        <span class="opacity-75">max</span>
      </label>
    </div>
  </div>
  <div class="bg-base-200 rounded-lg px-4 py-3 mb-3">
    <span class="block text-sm truncate mb-3">Backup codes</span>

    <div class="flex items-center gap-3 text-xs mb-3">
      <label class="flex items-center gap-3">
        <span class="text-xs truncate opacity-75">characters</span>
        <input
          type="text"
          placeholder="..."
          class="input input-xs max-w-[60px]"
          value={settings.backupCodes.minChars}
          oninput={(e) => change({ backupCodes: { minChars: e.target.value } })}
        />
        <span class="opacity-75">min</span>
      </label>
      <label class="flex items-center gap-3">
        <input
          type="text"
          placeholder="..."
          class="input input-xs max-w-[60px]"
          value={settings.backupCodes.maxChars}
          oninput={(e) => change({ backupCodes: { maxChars: e.target.value } })}
        />
        <span class="opacity-75">max</span>
      </label>
    </div>
    <div class="flex items-center gap-3 text-xs">
      <span class="text-xs opacity-75">require</span>
      <label class="flex items-center gap-3">
        <input
          type="text"
          placeholder="..."
          class="input input-xs max-w-[60px]"
          value={settings.backupCodes.total}
          oninput={(e) => change({ backupCodes: { total: e.target.value } })}
        />

        <span class="opacity-75">when generating a new set</span>
      </label>
    </div>
  </div>

  <p class="label-text-alt text-neutral-content opacity-75">Sessions</p>

  <div class="grow flex flex-col gap-1.5 mb-3">
    <label class="input input-bordered input-sm flex items-center gap-3">
      <span class="opacity-75 text-xs min-w-[35px]">cookie lifetime</span>
      <input
        type="text"
        class="grow placeholder:opacity-75"
        value={settings.sessions.lifetime}
        placeholder="expires when the browser exits..."
        oninput={(e) => change({ sessions: { lifetime: e.target.value } })}
      />
    </label>
    <label class="input input-bordered input-sm flex items-center gap-3 grow">
      <span class="opacity-75 text-xs min-w-[35px]">device lifetime</span>
      <input
        type="text"
        class="grow placeholder:opacity-75"
        placeholder="expires when the browser exits..."
        value={settings.devices.lifetime}
        oninput={(e) => change({ devices: { lifetime: e.target.value } })}
      />
    </label>
    <label class="input input-bordered input-sm flex items-center gap-3 grow">
      <span class="opacity-75 text-xs min-w-[35px]">inactive after</span>
      <input
        type="text"
        class="grow placeholder:opacity-75"
        placeholder="expires when the browser exits..."
        value={settings.sessions.inactive}
        oninput={(e) => change({ sessions: { inactive: e.target.value } })}
      />
    </label>
  </div>
</div>
