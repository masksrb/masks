<script>
import _ from "lodash-es";

import FactorWebauthn from "../factors/FactorWebauthn.svelte";
import FactorOtp from "../factors/FactorOtp.svelte";
import FactorPhoneNumber from "../factors/FactorPhoneNumber.svelte";
import FactorBackupCodes from "../factors/FactorBackupCodes.svelte";

let { ...props } = $props();

let factors = [
  props.auth?.client?.allowWebauthn ? FactorWebauthn : null,
  props.auth?.client?.allowPhones ? FactorPhoneNumber : null,
  props.auth?.client?.allowOtp ? FactorOtp : null,
  props.auth?.client?.allowBackupCodes ? FactorBackupCodes : null,
];
</script>

<div class="flex flex-col divide-y gap-1.5 divide-base-100 divide-dotted">
  {#each factors as Factor}
    <Factor {...props} />
  {/each}
</div>
