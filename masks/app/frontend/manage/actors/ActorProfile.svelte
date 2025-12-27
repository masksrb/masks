<script>
import Icon from "@iconify/svelte";
import ActorEmails from "./ActorEmails.svelte";
import ActorPhones from "./ActorPhones.svelte";
import ActorHardwareKeys from "./ActorHardwareKeys.svelte";
import ActorBackupCodes from "./ActorBackupCodes.svelte";
import ActorOtpSecrets from "./ActorOtpSecrets.svelte";
import ActorPassword from "./ActorPassword.svelte";
import ScopesEditor from "../ScopesEditor.svelte";
import Time from "@/components/Time.svelte";
import { iconifyProvider } from "@/lib";

let { actor, change } = $props();
</script>

<div class="flex flex-col gap-1.5">
  <p class="grow font-bold">Profile</p>
  <label class="input input-neutral flex items-center gap-3 w-full">
    <span class="label-xs opacity-75">full name</span>

    <input
      type="text"
      class="grow"
      value={actor.name}
      placeholder="..."
      oninput={(e) => change({ name: e.target.value || null })}
    />
  </label>

  <label class="input input-neutral flex items-center gap-3 w-full">
    <span class="label-xs opacity-75">nickname</span>

    <input
      type="text"
      class="grow w-full"
      value={actor.nickname}
      placeholder="..."
      oninput={(e) => change({ nickname: e.target.value || null })}
    />
  </label>

  {#if actor.singleSignOns?.length}
    <span class="label-xs mt-3">Single sign-on</span>

    <div class="flex flex-wrap gap-3">
      {#each actor.singleSignOns as sso}
        <div class="flex items-center gap-3 bg-base-100 rounded-lg p-1.5 pr-3">
          <div class="w-10 h-10 bg-base-300 rounded-lg p-1.5">
            <Icon icon={iconifyProvider(sso.provider)} height="100%" />
          </div>

          <div class="flex flex-col gap-0.5">
            <span class="text-white font-bold text-sm">{sso.identifier}</span>

            <div class="flex items-baseline gap-1.5">
              <span class="text-xs">{sso.provider.name}</span>
              <p class="label-xs">
                <Time timestamp={sso.createdAt} ago="old" />
              </p>
            </div>
          </div>
        </div>
      {/each}
    </div>
  {/if}

  <span class="label-xs mt-1.5">emails</span>

  <div class="mb-3">
    <ActorEmails {actor} />
  </div>

  <p class="grow font-bold">Credentials</p>

  <div class="mb-3">
    <ActorPassword {actor} {change} />
  </div>

  <div class="flex items-center gap-3 mb-1.5">
    <p class="text-sm label-sm grow font-bold">Secondary credentials</p>

    <div
      class={`badge badge-sm ${actor.secondFactor ? "badge-success" : "badge-warning"}`}
    >
      {actor.secondFactor ? "enabled" : "not set up"}
    </div>
  </div>

  <div class="rows-1.5 mb-3">
    {#if !actor.secondFactors.length}
      <div
        class="border-2 border-dashed rounded-lg border-neutral text-xs text-center opacity-75 p-6"
      >
        There are no secondary credentials set up for this actor...
      </div>
    {/if}

    {#if actor.phones?.length}
      <ActorPhones {actor} />
    {/if}

    {#if actor.hardwareKeys?.length}
      <ActorHardwareKeys {actor} />
    {/if}

    {#if actor.otpSecrets?.length}
      <ActorOtpSecrets {actor} />
    {/if}

    {#if actor.savedBackupCodesAt}
      <ActorBackupCodes {actor} />
    {/if}
  </div>

  <p class="grow font-bold">Scopes</p>

  <ScopesEditor
    required
    scopes={{ required: actor.scopes }}
    change={(r) => {
      change({ scopes: r.scopes.required });
    }}
  />
</div>
