<script>
  import { handshakeUrl } from "./lib/pairing.js";

  let { boot, failure } = $props();
</script>

<div class="min-h-screen flex items-center justify-center p-4">
  <div class="card bg-base-100 shadow-xl w-full max-w-lg">
    <div class="card-body gap-4">
      <h1 class="card-title">Connect this admin app</h1>

      <p class="text-sm opacity-80">
        This page is a client of {boot.tenant.name} like any other. Approving it registers it
        against <span class="font-mono text-xs">{boot.resource}</span> and grants it
        <span class="font-mono text-xs">masks:manage</span>. No secret is issued to this browser.
      </p>

      {#if failure}
        <div class="alert alert-error text-sm" role="alert">{failure}</div>
      {/if}

      <a class="btn btn-primary" href={handshakeUrl(boot)}>Approve as an administrator</a>

      <p class="text-xs opacity-60">
        You will be asked to sign in first if you are not already.
      </p>
    </div>
  </div>
</div>
