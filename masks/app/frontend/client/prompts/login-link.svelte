<script>
import { run, preventDefault, stopPropagation } from "svelte/legacy";

import { Unlink, Link, Send, Mail } from "lucide-svelte";
import PromptHeader from "../shared/PromptHeader.svelte";
import PromptIdentifier from "../shared/PromptIdentifier.svelte";
import PromptContinue from "../shared/PromptContinue.svelte";
import { onDestroy } from "svelte";

let { auth, loading, authorize } = $props();

let seconds = $state(5);
let cancelled = $state();
let done = $state();
let invalidCode = $state();

run(() => {
  invalidCode = auth?.warnings?.includes("invalid-code");
});

let countdown = setInterval(() => {
  seconds = seconds - 1;

  if (seconds == 0) {
    continuing = true;
    clearInterval(countdown);
  }
}, 1000);

run(() => {
  if (seconds === 0 && !cancelled && !done && !invalidCode) {
    setTimeout(() => {
      authorize({ event: "login-link:verify" });
      done = true;
    }, 500);
  }
});

let cancel = () => {
  clearInterval(countdown);
  seconds = 0;
  cancelled = true;
};

onDestroy(() => {
  if (countdown) {
    clearInterval(countdown);
  }
});
</script>

<PromptHeader
  heading={invalidCode
    ? "Invalid login link..."
    : cancelled
      ? "Press continue to log in..."
      : "Verifying your login link..."}
  client={auth.client}
/>
<PromptIdentifier
  identifier={auth?.actor?.loginEmail}
  alternate={auth?.actor?.nickname}
  {auth}
  class="my-6 pr-3"
>
  {@const SvelteComponent = invalidCode ? Unlink : Link}
  <SvelteComponent
    class={`mr-1.5 ${invalidCode ? "text-error" : ""} ${!cancelled && !done ? "animate-pulse" : ""}`}
  />
</PromptIdentifier>

<div class="flex flex-col md:flex-row md:items-center md:gap-4">
  <PromptContinue
    {loading}
    disabled={!cancelled}
    class={`min-w-[150px] ${invalidCode ? "animate-denied btn-error" : "btn-primary"}`}
    event="login-link:verify"
  >
    {invalidCode ? "failed" : !cancelled ? "verifying" : "verify"}

    {#if seconds > 0}
      <span class="opacity-75">in {seconds || ""}</span>
    {/if}
  </PromptContinue>

  {#if !invalidCode}
    {#if !cancelled}
      <span class="opacity-75 text-lg ml-1.5 hidden md:flex"> or </span>

      <button
        onclick={stopPropagation(preventDefault(cancel))}
        class="px-0 !min-w-0 btn-link text-base-content"
      >
        cancel
      </button>
    {:else}
      <span class="opacity-75 max-w-[300px] ml-3 text-sm">
        Your login link will expire soon. If you don't recognize it, delete the
        original email and close this window.
      </span>
    {/if}
  {/if}
</div>
