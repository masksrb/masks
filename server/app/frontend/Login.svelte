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

const SURFACES = { consent: "grant", setup: "grant" };

$effect(() => {
  const surface = SURFACES[login.prompt] ?? "challenge";
  const column = document.querySelector(".auth-col");

  if (!column) return;

  for (const name of ["challenge", "grant"]) {
    column.classList.toggle(`surface-${name}`, name === surface);
  }

  document.querySelector(".auth-id")?.toggleAttribute(
    "hidden",
    surface !== "challenge",
  );
});
</script>

<Warnings {login} />

{#key login.prompt}
  <div class="prompt-in flow">
    {#if Prompt}
      <Prompt {login} />
    {:else}
      <span class="state state-bad">{login.t("stopped")}</span>

      <h1 class="prompt-title">{login.t("halted")}</h1>

      <button
        type="button"
        class="action action-quiet action-fit"
        onclick={() => login.startOver()}
      >
        {login.t("start_over")}
      </button>
    {/if}
  </div>
{/key}
