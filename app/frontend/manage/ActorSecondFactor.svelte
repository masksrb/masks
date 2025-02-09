<script>
  import Alert from "@/components/Alert.svelte";
  import ActorPassword from "./ActorPassword.svelte";
  import ActorEmails from "./ActorEmails.svelte";
  import ActorPhones from "./ActorPhones.svelte";
  import ActorHardwareKeys from "./ActorHardwareKeys.svelte";
  import ActorBackupCodes from "./ActorBackupCodes.svelte";
  import ActorOtpSecrets from "./ActorOtpSecrets.svelte";

  let { actor, change } = $props();
</script>

<div class="flex flex-col gap-1.5 mb-1.5 dark">
  <div class="flex items-center gap-3 mb-1.5">
    <p class="grow font-bold">Secondary credentials</p>

    <div
      class={`badge badge-sm ${actor.secondFactor ? "badge-success" : "badge-warning"}`}
    >
      {actor.secondFactor ? "enabled" : "not set up"}
    </div>
  </div>

  <div class="flex flex-col gap-3">
    {#if !actor.savedBackupCodesAt && !actor.secondFactors.length}
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
</div>
