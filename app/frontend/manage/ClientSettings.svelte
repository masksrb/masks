<script>
  import ScopesEditor from "./ScopesEditor.svelte";

  let { client, change, settings, ...props } = $props();
  let advanced2fa = $state();
</script>

<div class="flex flex-col gap-3">
  <div class="bg-base-200 rounded-lg px-4 pt-2 pb-3 rows-3">
    <h3 class="font-bold text-xs my-1.5">Allow login with...</h3>

    <div class="cols-3 flex-wrap gap-y-0.5">
      <label class="label cursor-pointer gap-1.5">
        <input
          type="checkbox"
          class="toggle toggle-xs"
          checked={client.allowNicknames}
          onclick={(e) => change({ allowNicknames: e.target.checked })}
        />
        <span class="label-xs"> nickname </span>
      </label>

      <label class="label cursor-pointer gap-1.5">
        <input
          type="checkbox"
          class="toggle toggle-xs"
          checked={client.allowEmails}
          onclick={(e) => change({ allowEmails: e.target.checked })}
        />
        <span class="label-xs"> e-mail </span>
      </label>

      <label class="label cursor-pointer gap-1.5">
        <input
          type="checkbox"
          class="toggle toggle-xs"
          checked={client.allowPasswords}
          onclick={(e) => change({ allowPasswords: e.target.checked })}
        />
        <span class="label-xs"> password </span>
      </label>

      <label class="label cursor-pointer gap-1.5">
        <input
          type="checkbox"
          class="toggle toggle-xs"
          checked={client.allowLoginLinks}
          onclick={(e) => change({ allowLoginLinks: e.target.checked })}
        />
        <span class="label-xs"> magic links </span>
      </label>

      <label class="label cursor-pointer gap-1.5">
        <input
          type="checkbox"
          class="toggle toggle-xs"
          checked={client.allowSso}
          onclick={(e) => change({ allowSso: e.target.checked })}
        />
        <span class="label-xs"> single sign-on</span>
      </label>
    </div>

    <div class="divider my-0"></div>

    <label class="label cursor-pointer gap-1.5">
      {#if client.allowFactor2}
        <span class="label-xs"
          >Two-factor auth is <b class="text-success">enabled</b>

          <span class="opacity-75"
            >(<button
              class="underline"
              onclick={() => (advanced2fa = !advanced2fa)}
              >{advanced2fa ? "close" : "customize"}</button
            >)</span
          >
        </span>
      {:else}
        <span class="label-xs"
          >Two-factor auth is <b class="text-warning">disabled</b></span
        >
      {/if}
      <input
        type="checkbox"
        class="toggle toggle-xs"
        checked={client.allowFactor2}
        onclick={(e) => change({ allowFactor2: e.target.checked })}
      />
    </label>

    {#if client.allowFactor2 && advanced2fa}
      <label class="label cursor-pointer gap-1.5">
        <span class="label-xs ml-3"> OTP </span>
        <input
          type="checkbox"
          class="toggle toggle-xs"
          checked={client.allowOtp}
          onclick={(e) => change({ allowOtp: e.target.checked })}
        />
      </label>

      <label class="label cursor-pointer gap-1.5">
        <span class="label-xs ml-3"> SMS verification</span>
        <input
          type="checkbox"
          class="toggle toggle-xs"
          checked={client.allowPhones}
          onclick={(e) => change({ allowPhones: e.target.checked })}
        />
      </label>

      <label class="label cursor-pointer gap-1.5">
        <span class="label-xs ml-3"> Webauthn </span>
        <input
          type="checkbox"
          class="toggle toggle-xs"
          checked={client.allowWebauthn}
          onclick={(e) => change({ allowWebauthn: e.target.checked })}
        />
      </label>

      <label class="label cursor-pointer gap-1.5 ml-3">
        <span class="label-xs"> Backup codes</span>
        <input
          type="checkbox"
          class="toggle toggle-xs"
          checked={client.allowBackupCodes}
          onclick={(e) => change({ allowBackupCodes: e.target.checked })}
        />
      </label>
    {/if}

    <label class="label cursor-pointer gap-1.5">
      <span class="label-xs"> Profile management</span>
      <input
        type="checkbox"
        class="toggle toggle-xs"
        checked={client.allowProfiles}
        onclick={(e) => change({ allowProfiles: e.target.checked })}
      />
    </label>

    <label class="label cursor-pointer gap-1.5">
      <span class="label-xs"> Public discovery </span>
      <input
        type="checkbox"
        class="toggle toggle-xs"
        checked={client.allowDiscovery}
        onclick={(e) => change({ allowDiscovery: e.target.checked })}
      />
    </label>
  </div>
</div>
