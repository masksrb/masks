<script>
import { untrack } from "svelte";
import { createLogin } from "./lib/login.svelte.js";
import Warnings from "./shared/Warnings.svelte";
import BackupCode from "./prompts/backup-code.svelte";
import FirstFactor from "./prompts/first-factor.svelte";
import Identify from "./prompts/identify.svelte";
import SecondFactor from "./prompts/second-factor.svelte";
import Settled from "./prompts/settled.svelte";
import Setup from "./prompts/setup.svelte";

const prompts = {
  setup: Setup,
  identify: Identify,
  "first-factor": FirstFactor,
  "second-factor": SecondFactor,
  "backup-code": BackupCode,
  settled: Settled,
};

let { auth } = $props();

const login = createLogin(untrack(() => auth));
const Prompt = $derived(prompts[login.prompt]);
</script>

<div class="flex flex-col gap-4">
  <Warnings {login} />

  {#if Prompt}
    <Prompt {login} />
  {:else}
    <h1 class="text-2xl font-bold">Something went wrong</h1>
    <p class="text-sm opacity-75">
      This sign-in cannot continue. Start over and try again.
    </p>
    <button type="button" class="btn btn-primary" onclick={() => login.startOver()}>
      Start over
    </button>
  {/if}
</div>
