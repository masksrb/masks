<script>
  let { settings, change, loading, errors, save, ...props } = $props();
</script>

<div class="flex flex-col gap-1.5">
  <div clss="mb-1.5 pl-1.5">
    <p class="label-xs text-neutral-content opacity-75">Credentials</p>
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
          value={settings.nicknameMinChars}
          oninput={(e) =>
            change({
              nicknameMinChars: e.target.value ? parseInt(e.target.value) : "",
            })}
        />
        <span class="opacity-75">min</span>
      </label>
      <label class="flex items-center gap-3">
        <input
          type="text"
          placeholder="..."
          class="input input-xs max-w-[60px]"
          value={settings.nicknameMaxChars}
          oninput={(e) =>
            change({
              nicknameMaxChars: e.target.value ? parseInt(e.target.value) : "",
            })}
        />

        <span class="opacity-75">max</span>
      </label>
    </div>
    <div class="flex items-center gap-3 text-xs mt-1.5">
      <span class="label-xs">format</span>
      <label class="flex items-center gap-3 grow">
        <input
          type="text"
          placeholder="..."
          class="input input-xs w-full grow font-mono"
          value={settings.nicknameFormat}
          oninput={(e) => change({ nicknameFormat: e.target.value })}
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
          value={settings.passwordMinChars}
          oninput={(e) =>
            change({
              passwordMinChars: e.target.value ? parseInt(e.target.value) : "",
            })}
        />
        <span class="opacity-75">min</span>
      </label>
      <label class="flex items-center gap-3">
        <input
          type="text"
          placeholder="..."
          class="input input-xs max-w-[60px]"
          value={settings.passwordMaxChars}
          oninput={(e) =>
            change({
              passwordMaxChars: e.target.value ? parseInt(e.target.value) : "",
            })}
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
          value={settings.backupCodeMinChars}
          oninput={(e) =>
            change({
              backupCodeMinChars: e.target.value
                ? parseInt(e.target.value)
                : "",
            })}
        />
        <span class="opacity-75">min</span>
      </label>
      <label class="flex items-center gap-3">
        <input
          type="text"
          placeholder="..."
          class="input input-xs max-w-[60px]"
          value={settings.backupCodeMaxChars}
          oninput={(e) =>
            change({
              backupCodeMaxChars: e.target.value
                ? parseInt(e.target.value)
                : "",
            })}
        />
        <span class="opacity-75">max</span>
      </label>
    </div>
    <div class="flex items-center gap-3 text-xs">
      <span class="label-xs">require</span>
      <label class="flex items-center gap-3">
        <input
          type="text"
          placeholder="..."
          class="input input-xs max-w-[60px]"
          value={settings.backupCodeLimit}
          oninput={(e) =>
            change({
              backupCodeLimit: e.target.value ? parseInt(e.target.value) : "",
            })}
        />

        <span class="opacity-75">when generating a new set</span>
      </label>
    </div>
  </div>

  <p class="label-xs text-neutral-content opacity-75">Sessions</p>

  <div class="grow flex flex-col gap-1.5 mb-3">
    <label class="input input-bordered input-sm flex items-center gap-3">
      <span class="opacity-75 text-xs min-w-[35px]">cookie lifetime</span>
      <input
        type="text"
        class="grow placeholder:opacity-75"
        value={settings.sessionCookieLifetime}
        placeholder="expires when the browser exits..."
        oninput={(e) => change({ sessionCookieLifetime: e.target.value })}
      />
    </label>
    <label class="input input-bordered input-sm flex items-center gap-3 grow">
      <span class="opacity-75 text-xs min-w-[35px]">device lifetime</span>
      <input
        type="text"
        class="grow placeholder:opacity-75"
        placeholder="expires when the browser exits..."
        value={settings.deviceCookieLifetime}
        oninput={(e) => change({ deviceCookieLifetime: e.target.value })}
      />
    </label>
    <label class="input input-bordered input-sm flex items-center gap-3 grow">
      <span class="opacity-75 text-xs min-w-[35px]">inactive after</span>
      <input
        type="text"
        class="grow placeholder:opacity-75"
        placeholder="expires when the browser exits..."
        value={settings.sessionInactive}
        oninput={(e) => change({ sessionInactive: e.target.value })}
      />
    </label>
  </div>
</div>
