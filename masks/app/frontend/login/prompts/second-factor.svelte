<script>
import _ from "lodash-es";

import Verification from "../factors/Verification.svelte";

let { ...props } = $props();
</script>

<div class="rows-1.5">
  <div>
    <Verification
      {...props}
      allow={{ second: true, backupCodes: true }}
      identifier
    >
      {#snippet subheading()}
        to {props.auth.client.name}
      {/snippet}
    </Verification>
  </div>
</div>
