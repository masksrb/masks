<script>
  import { handshakeUrl } from "./lib/pairing.js";

  let { boot, failure } = $props();
</script>

<div class="auth-page">
  <main class="auth-card">
    <div class="auth-rail">{boot.tenant.name}</div>

    <div class="auth-body flow">
      <div class="prompt-head">
        <h1 class="prompt-title">Connect this console</h1>
        <p class="prompt-lede">
          It is a client like any other. Approving registers it against
          <span class="aside-mono">{boot.resource}</span> and grants it
          <span class="aside-mono">masks:manage</span>.
        </p>
      </div>

      {#if failure}
        <div class="note note-bad" role="alert">{failure}</div>
      {/if}

      <a class="action" href={handshakeUrl(boot)}>Approve as an administrator</a>

      <p class="aside">
        No secret is issued to this browser. You are asked to sign in first if you are not already.
      </p>
    </div>
  </main>
</div>
