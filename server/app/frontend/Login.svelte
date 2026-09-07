<script>
import { untrack } from "svelte";
import { createLogin } from "./lib/login.svelte.js";
import Action from "./shared/Action.svelte";
import Head from "./shared/Head.svelte";
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

let frame = $state(null);
let entering = $state(false);
let leaving = $state(0);

const still = () =>
  typeof matchMedia === "function" &&
  matchMedia("(prefers-reduced-motion: reduce)").matches;

$effect.pre(() => {
  login.prompt;

  const height = untrack(() => (still() ? 0 : (frame?.offsetHeight ?? 0)));

  leaving = height;
  entering = height > 0;
});

$effect(() => {
  const surface = SURFACES[login.prompt] ?? "challenge";
  const paired = login.prompt === "settled" && Boolean(login.client?.name);
  const column = document.querySelector(".auth-col");

  if (!column) return;

  for (const name of ["challenge", "grant"]) {
    column.classList.toggle(`surface-${name}`, name === surface);
  }

  document
    .querySelector(".auth-id")
    ?.toggleAttribute("hidden", surface !== "challenge" || paired);
});

$effect(() => {
  login.prompt;

  const node = frame;
  const from = untrack(() => leaving);

  if (!node || !from) return;

  const to = node.offsetHeight;

  if (to !== from) {
    node.classList.add("gate-moving");

    const move = node.animate(
      [{ height: `${from}px` }, { height: `${to}px` }],
      { duration: 300, easing: "cubic-bezier(0.2, 0.8, 0.2, 1)" },
    );

    move.finished
      .catch(() => {})
      .then(() => node.classList.remove("gate-moving"));
  }

  const timer = setTimeout(() => {
    entering = false;
  }, 500);

  return () => clearTimeout(timer);
});
</script>

<Warnings {login} />

<div class="gate" class:gate-enter={entering} bind:this={frame}>
  {#key login.prompt}
    {#if Prompt}
      <Prompt {login} />
    {:else}
      <div class="over">
        <Head
          {login}
          tone="bad"
          title={login.t("halted")}
          lede={login.t("halted_lede")}
        />

        <Action
          {login}
          quiet
          label={login.t("start_over")}
          working={login.t("working")}
          busy={login.loading}
          onclick={() => login.startOver()}
        />
      </div>
    {/if}
  {/key}
</div>
