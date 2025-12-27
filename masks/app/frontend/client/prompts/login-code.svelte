<script>
import { run } from "svelte/legacy";

import Time from "svelte-time";
import { MailSearch as Mail } from "lucide-svelte";
import CodeInput from "@/components/CodeInput.svelte";
import PromptHeader from "../shared/PromptHeader.svelte";
import PromptIdentifier from "../shared/PromptIdentifier.svelte";
import PromptContinue from "../shared/PromptContinue.svelte";
import Alert from "@/components/Alert.svelte";

let { auth, authorize, loading, startOver } = $props();

let value = $state();
let code = $state([]);
let complete = $state();
let reset = $state();
let denied = $state();
let label;

let onsubmit = () => {
  authorize({
    event: "login-link:verify",
    updates: { code: value, resetPassword: reset },
  });
};
</script>

<PromptHeader
  heading="Enter your login code..."
  client={auth.client}
  class="mb-3 md:mb-6"
/>

{#if auth?.loginLink}
  <Alert icon={Mail} type="info" class="mb-3">
    Check your email for a 7-character login code and enter it below. Your login
    code expires <b><Time timestamp={auth?.loginLink?.expiresAt} relative /></b
    >.
  </Alert>
{/if}

<PromptIdentifier {auth} class="mb-3" {startOver} />

<form action="#" {onsubmit}>
  <div class="flex flex-col items-center mb-1.5">
    <CodeInput
      {auth}
      length={7}
      bind:code
      bind:value
      bind:complete
      class="input-lg"
    />
  </div>

  {#if auth?.client?.allowPasswords}
    <label
      class={`label cursor-pointer flex items-center gap-3 mt-1.5 mb-6 ${reset ? "" : "opacity-50"}`}
    >
      <input type="checkbox" class="toggle toggle-sm" bind:checked={reset} />

      <span class="grow text-left text-sm">Change password after login</span>
    </label>
  {:else}
    <div class="mb-6"></div>
  {/if}

  <div class="flex flex-col md:flex-row md:items-center md:gap-4">
    <PromptContinue
      type="submit"
      {label}
      {denied}
      {loading}
      {authorize}
      event="login-link:verify"
      updates={{ email_code: value, reset_password: reset }}
      disabled={!complete}
      class={denied ? "btn-warning" : "btn-primary"}
    />

    {#if auth?.client?.allowPasswords}
      <span class="opacity-75 text-lg ml-1.5 hidden md:flex"> or </span>

      <PromptContinue
        class="px-0 w-auto btn-link text-base-content"
        event="login-link:password"
        {authorize}
      >
        enter your password...
      </PromptContinue>
    {/if}
  </div>
</form>
