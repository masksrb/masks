<script>
import { Info } from "lucide-svelte";
import ScopesEditor from "./ScopesEditor.svelte";

let { client, change, settings, ...props } = $props();
let advancedSecondFactor = $state();
</script>

<div class="flex flex-col gap-3">
  <div class="rows-3">
    <div class="cols-1.5 md:text-base text-xs">
      <label class="label cursor-pointer gap-1.5 box bg-base-300 grow">
        <input
          type="checkbox"
          class="checkbox checkbox-xs"
          checked={client.allowLogin}
          onclick={(e) => change({ allowLogin: e.target.checked })}
        />
        <h3 class="font-bold text-base-content truncate">Login</h3>
      </label>

      <label class="label cursor-pointer gap-1.5 box bg-base-300 grow">
        <input
          type="checkbox"
          class="checkbox checkbox-xs"
          checked={client.allowSignup}
          onclick={(e) => change({ allowSignup: e.target.checked })}
        />
        <h3 class="font-bold text-base-content truncate">Signup</h3>
      </label>

      <label class="label cursor-pointer gap-1.5 box bg-base-300 grow">
        <input
          type="checkbox"
          class="checkbox checkbox-xs"
          checked={client.allowProfiles}
          onclick={(e) => change({ allowProfiles: e.target.checked })}
        />
        <h3 class="font-bold text-base-content truncate">Profiles</h3>
      </label>
    </div>
  </div>

  {#if client.allowLogin || client.allowSignup || client.allowProfiles}
    <div class="bg-base-200 rows-3 box-snug">
      <span class="label-xs mt-1.5"> Credentials </span>
      <div class="cols-3 flex-wrap gap-y-3 my-1.5">
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

      <label class="label cursor-pointer gap-1.5 mb-1.5">
        {#if client.allowSecondFactor}
          <span class="label-xs"
            ><span class="text-base-content">Secondary credentials</span> are
            <b class="text-success">enabled</b>
          </span>
        {:else}
          <span class="label-xs"
            >Two-factor auth is <b class="text-warning">disabled</b></span
          >
        {/if}
        <input
          type="checkbox"
          class="toggle toggle-xs"
          checked={client.allowSecondFactor}
          onclick={(e) => change({ allowSecondFactor: e.target.checked })}
        />

        {#if client.allowSecondFactor}
          <span class="opacity-75 text-xs"
            >(<button
              class="underline"
              onclick={() => (advancedSecondFactor = !advancedSecondFactor)}
              >{advancedSecondFactor ? "close" : "customize"}</button
            >)</span
          >
        {/if}
      </label>

      {#if client.allowSecondFactor && advancedSecondFactor}
        <div class="rows-3 mb-1.5">
          <label class="label cursor-pointer gap-1.5">
            <input
              type="checkbox"
              class="toggle toggle-xs"
              checked={client.allowOtp}
              onclick={(e) => change({ allowOtp: e.target.checked })}
            />
            <span class="label-xs ml-1.5"> OTP </span>
          </label>

          <label class="label cursor-pointer gap-1.5">
            <input
              type="checkbox"
              class="toggle toggle-xs"
              checked={client.allowPhones}
              onclick={(e) => change({ allowPhones: e.target.checked })}
            />
            <span class="label-xs ml-1.5"> SMS verification</span>
          </label>

          <label class="label cursor-pointer gap-1.5">
            <input
              type="checkbox"
              class="toggle toggle-xs"
              checked={client.allowWebauthn}
              onclick={(e) => change({ allowWebauthn: e.target.checked })}
            />
            <span class="label-xs ml-1.5"> Webauthn </span>
          </label>

          <label class="label cursor-pointer gap-1.5">
            <input
              type="checkbox"
              class="toggle toggle-xs"
              checked={client.allowBackupCodes}
              onclick={(e) => change({ allowBackupCodes: e.target.checked })}
            />
            <span class="label-xs ml-1.5"> Backup codes</span>
          </label>
        </div>
      {/if}
    </div>

    <div class="bg-base-200 rows-3 box">
      <label class="input input-sm input-neutral">
        <span>Terms URL</span>
        <input
          value={client.termsUrl}
          type="text"
          class="w-full"
          placeholder="Enter a URL to your terms & conditions page..."
          accept=".css"
          oninput={(e) => change({ termsUrl: e.target.value })}
        />
      </label>

      <span class="label-xs cols-1.5 pl-1.5">
        <Info size="14" />
        If specified, terms are linked during login and signup.
      </span>
    </div>
  {/if}
</div>
