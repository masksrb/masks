<script>
  import { callbackUri, handshakeUrl, SCOPE } from "./lib/pairing.js";

  let { boot, failure } = $props();

  const mark = (name) => name.trim().slice(0, 1).toUpperCase();
</script>

<div class="auth-page">
  <main class="auth-col surface-grant">
    <div class="auth-pair">
      <span class="auth-mark auth-mark-client" aria-hidden="true">M</span>
      <span class="auth-wire"></span>
      <span class="auth-mark" aria-hidden="true">{mark(boot.tenant.name)}</span>
    </div>

    <div class="flow">
      <div class="prompt-head">
        <h1 class="prompt-title">Connect this console</h1>
        <p class="prompt-lede">
          It is a client like any other, and it is registered the same way.
        </p>
      </div>

      {#if failure}
        <div class="note note-bad" role="alert">{failure}</div>
      {/if}

      <div class="slab">
        <div class="ledger-row">
          <span class="ledger-label">Access</span>
          <span class="ledger-value aside-mono">{SCOPE.join(" ")}</span>
        </div>

        <div class="ledger-row">
          <span class="ledger-label">Signs you in at</span>
          <span class="ledger-value aside-mono">{boot.resource}</span>
        </div>

        <div class="ledger-row">
          <span class="ledger-label">Returns to</span>
          <span class="ledger-value aside-mono">{callbackUri(boot)}</span>
        </div>
      </div>

      <a class="action" href={handshakeUrl(boot)}>Approve as an administrator</a>

      <p class="aside">
        No secret is issued to this browser. You are asked to sign in first if you are not already.
      </p>
    </div>
  </main>
</div>
