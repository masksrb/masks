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
  import PromptContinue from "../PromptContinue.svelte";
  import FactorWebauthn from "./FactorWebauthn.svelte";
  import FactorOtp from "./FactorOtp.svelte";
  import FactorPhoneNumber from "./FactorPhoneNumber.svelte";
  import FactorBackupCodes from "./FactorBackupCodes.svelte";
  import Card from "@/components/Card.svelte";

  let { required, loading = $bindable(), ...props } = $props();
  let { authorize } = props;

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

  let Factor = $derived(factor || defaultFactor);
  let lockedTab = $state();
  let setLocked = (v) => {
    lockedTab = v;
  };
</script>

<div>
  {#if Object.values(enabledFactors).length > 1}
    <div class="overflow-auto pt-1.5 pl-3">
      <div
        role="tablist"
        class="tabs tabs-bordered tabs-xs justify-start w-full"
      >
        {#each Object.values(enabledFactors) as { component, choose }, index}
          <button
            onclick={stopPropagation(
              preventDefault(() => switchFactor(lockedTab ? Factor : component))
            )}
            type="button"
            role="tab"
            class={`${component == Factor ? "tab tab-active" : lockedTab ? "tab tab-disabled" : "tab opacity-75"} whitespace-nowrap pb-6 text-left`}
            >{choose}</button
          >
        {/each}
      </div>
    </div>
  {/if}

  <Factor {...props} authorizing {setLocked} />
</div>

<div class="text-center pt-1.5 rounded mt-3 text-xs opacity-75">
  {#if Factor == FactorBackupCodes}
    <button
      type="button"
      class="btn btn-xs text-error"
      onclick={stopPropagation(
        preventDefault(() => switchFactor(previousFactor || defaultFactor))
      )}>cancel</button
    >
  {:else}
    <button
      type="button"
      class="btn btn-xs"
      onclick={stopPropagation(
        preventDefault(() => switchFactor(FactorBackupCodes))
      )}>enter a backup code</button
    >
  {/if}
</div>
