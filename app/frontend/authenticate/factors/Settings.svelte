<script>
  import { preventDefault, stopPropagation } from "svelte/legacy";

  import _ from "lodash-es";

  import {
    Check,
    ChevronLeft as Back,
    AlertTriangle,
    KeySquare,
    Binary,
    QrCode,
    Phone,
    Fingerprint,
    Unlock,
    Lock,
  } from "lucide-svelte";

  import Alert from "@/components/Alert.svelte";
  import PromptContinue from "../shared/PromptContinue.svelte";
  import FactorWebauthn from "./FactorWebauthn.svelte";
  import FactorOtp from "./FactorOtp.svelte";
  import FactorPhoneNumber from "./FactorPhoneNumber.svelte";
  import FactorBackupCodes from "./FactorBackupCodes.svelte";
  import Card from "@/components/Card.svelte";

  let { required, loading = $bindable(), ...props } = $props();
  let { authorize } = $derived(props);

  let auth = $derived(props.auth);
  let enabled = $derived(auth?.actor?.secondFactor);

  let securityKeys = $derived(
    auth?.actor?.secondFactors?.filter((f) => f.__typename == "HardwareKey")
  );

  let phones = $derived(
    auth?.actor?.secondFactors?.filter((f) => f.__typename == "Phone")
  );

  let totp = $derived(
    auth?.actor?.secondFactors?.filter((f) => f.__typename == "OtpSecret")
  );

  let backupCodes = $derived(auth?.actor?.savedBackupCodesAt);

  let enabledFactors = $derived(
    [
      securityKeys?.length
        ? {
            component: FactorWebauthn,
            choose: "security key",
          }
        : null,
      phones?.length
        ? {
            component: FactorPhoneNumber,
            choose: "phone number",
          }
        : null,
      totp?.length
        ? {
            component: FactorOtp,
            choose: "one-time code",
          }
        : null,
    ].filter(Boolean)
  );

  let secondFactor = $derived(auth?.actor?.secondFactors?.length);

  let isValid = $derived(backupCodes && secondFactor);
  let canContinue = $derived(!enabled && isValid);

  let heading = $derived(
    enabled ? "Verify your credentials..." : "Add your credentials..."
  );

  let factors = [
    FactorWebauthn,
    FactorPhoneNumber,
    FactorOtp,
    FactorBackupCodes,
  ];

  let factor = $state();
  let defaultFactor = $derived(
    securityKeys?.length
      ? FactorWebauthn
      : phones?.length
        ? FactorPhoneNumber
        : totp?.length
          ? FactorOtp
          : FactorBackupCodes
  );
  let previousFactor = $state();

  let switchFactor = (v) => {
    previousFactor = factor;
    factor = v;
  };

  let cancelFactor = () => {
    switchFactor(null);
  };

  let currentFactor = $derived(factor || defaultFactor);

  let lockedTab = $state();
  let setLocked = (v) => {
    lockedTab = v;
  };
</script>

<div class="flex flex-col divide-y gap-1.5 divide-base-100 divide-dotted">
  <div>
    <Alert
      type={isValid ? "success" : "warn"}
      class="mb-3"
      icon={required && !isValid ? Unlock : null}
    >
      <div class="cols-1.5">
        <div class="rows gap-0.5 grow">
          <div class="cols-3 grow">
            {#if required}
              <p class="">
                {#if !canContinue}
                  Add your two-factor auth credentials to continue...
                {:else}
                  Press continue to enable two-factor auth on your account...
                {/if}
              </p>
            {:else}
              <p class="font-bold text-right">Two-factor auth</p>

              {#if isValid}
                <div class="badge badge-success badge-sm badge-icon w-5 p-0">
                  <Lock size="10" />
                </div>
              {:else}
                <div class="badge badge-warning badge-sm w-5 p-0">
                  <Unlock size="10" />
                </div>
              {/if}
            {/if}

            <div class="grow"></div>

            {#if !required}
              <button
                class="btn btn-xs btn-ghost -mr-1.5"
                onclick={props?.onclose}
              >
                <Back size="14" />

                Back to your profile
              </button>
            {/if}
          </div>
        </div>

        {#if required && canContinue}
          <PromptContinue
            {auth}
            {loading}
            {authorize}
            event="second-factor:enable"
            disabled={!canContinue}
            class="btn-success !btn-md"
          />
        {/if}
      </div></Alert
    >
  </div>

  {#each factors as Factor}
    <Factor {...props} />
  {/each}
</div>
