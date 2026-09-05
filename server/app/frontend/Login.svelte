<script>
import { untrack } from "svelte";
import { createLogin } from "./lib/login.svelte.js";
import Warnings from "./shared/Warnings.svelte";
import AcceptInvitation from "./prompts/accept-invitation.svelte";
import BackupCode from "./prompts/backup-code.svelte";
import Consent from "./prompts/consent.svelte";
import FirstFactor from "./prompts/first-factor.svelte";
import Identify from "./prompts/identify.svelte";
import ResetPassword from "./prompts/reset-password.svelte";
import SecondFactor from "./prompts/second-factor.svelte";
import Settled from "./prompts/settled.svelte";
import Setup from "./prompts/setup.svelte";

const prompts = {
  setup: Setup,
  "accept-invitation": AcceptInvitation,
  identify: Identify,
  "reset-password": ResetPassword,
  "first-factor": FirstFactor,
  "second-factor": SecondFactor,
  "backup-code": BackupCode,
  consent: Consent,
  settled: Settled,
};

let { auth } = $props();

const login = createLogin(untrack(() => auth));
const Prompt = $derived(prompts[login.prompt]);

const GRANTING = ["consent"];

$effect(() => {
  const granting = GRANTING.includes(login.prompt);

  document.querySelector(".auth-card")?.classList.toggle("grant", granting);
});
</script>

<Warnings {login} />

{#key login.prompt}
  <div class="prompt-in flow">
    {#if Prompt}
      <Prompt {login} />
    {:else}
      <div class="prompt-head">
        <h1 class="prompt-title">Something went wrong</h1>
        <p class="prompt-lede">
          This sign-in cannot continue. Start over and try again.
        </p>
      </div>

      <button type="button" class="action" onclick={() => login.startOver()}>
        Start over
      </button>
    {/if}
  </div>
{/key}
