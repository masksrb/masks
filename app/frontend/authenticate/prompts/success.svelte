<script>
  import PromptContinue from "../shared/PromptContinue.svelte";
  import Identicon from "@/components/Identicon.svelte";
  import { onMount } from "svelte";
  import { redirectTimeout } from "@/util";

  let { auth } = $props();

  let manual = $state();
  let redirect = (e) => {
    e?.preventDefault();
    e?.stopPropagation();

    window.location.replace(auth.redirectUri);
  };

  onMount(() => {
    redirectTimeout((timedOut) => {
      if (timedOut) {
        manual = true;
      } else {
        redirect();
      }
    }, 2000);
  });
</script>

<div class="py-12 animate-fade-in-1s">
  <div class="mb-6">
    <div
      class="mx-auto text-center w-[100px] h-[100px] bg-black rounded-lg shadow-xl"
    >
      {#if auth?.actor?.avatar}
        <img src={auth.actor.avatar} class="object-cover" alt="avatar" />
      {:else}
        <Identicon id={auth.actor.identiconId} />
      {/if}
    </div>

    <div class="text-center pt-1.5 opacity-75 text-sm">
      {auth?.actor?.identifier}
    </div>
  </div>

  <div class="text-center">
    <div class={`text-2xl leading-relaxed ${manual ? "" : "animate-pulse"}`}>
      {manual ? "Logged in" : "Continuing"} to<br /><a
        href={auth.redirectUri}
        class="font-bold">{auth?.client?.name}</a
      >...
    </div>
  </div>

  {#if manual}
    <div class="flex justify-center mt-10">
      <PromptContinue class="btn-success" onclick={redirect} />
    </div>
  {:else}
    <div class="text-center pt-6">
      <span
        class="loading loading-spinner loading-lg mx-auto loading-dots text-success"
      ></span>
    </div>
  {/if}
</div>
