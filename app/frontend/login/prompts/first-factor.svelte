<script>
  import { X, Send, Mail } from "lucide-svelte";
  import Alert from "@/components/Alert.svelte";
  import PromptHeader from "../shared/PromptHeader.svelte";
  import PromptIdentifier from "../shared/PromptIdentifier.svelte";
  import PromptContinue from "../shared/PromptContinue.svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import { getContext } from "svelte";

  let { auth, authorize, loading = $bindable(), startOver } = $props();

  let allowLoginLinks = $derived(auth?.client?.allowLoginLinks);
  let allowPasswords = $derived(auth?.client?.allowPasswords);

  let valid = $state(false);
  let password = $state();
  let denied = $state();
  let onsubmit = (e) => {
    e.preventDefault();
    e.stopPropagation();

    if (!valid) {
      return;
    }

    authorize({ event: "password:verify", updates: { password } });
  };

  $effect(() => {
    denied = auth?.warnings?.includes("invalid-credentials");
  });
</script>

<PromptHeader
  heading={allowPasswords ? "Enter your password..." : "Send a login link..."}
  client={auth.client}
  redirectUri={auth.redirectUri}
  class="mb-6"
/>

{#if auth?.warnings?.includes("expired-login-link")}
  <Alert icon={X} type="warn">Your 7-character code has expired.</Alert>
{/if}

<PromptIdentifier {auth} {startOver} class={allowPasswords ? "mb-3" : "mb-6"} />

{#if allowPasswords}
  <form action="#" {onsubmit}>
    <PasswordInput
      {auth}
      class="input-lg mb-6"
      placeholder="Your password"
      bind:value={password}
      bind:valid
      autofocus={getContext("autofocus")}
    />

    <div class="flex flex-col md:flex-row md:items-center md:gap-4">
      <PromptContinue
        type="submit"
        {loading}
        {denied}
        disabled={allowPasswords && !valid}
        class={denied ? "btn-warning" : "btn-accent"}
      />

      {#if auth?.loginLink || allowLoginLinks}
        <span class="opacity-75 text-lg ml-1.5 hidden md:flex"> or </span>

        <PromptContinue
          class="px-0 w-auto btn-link text-base-content"
          event="login-link:start"
          {authorize}
        >
          {#if auth?.loginLink}
            enter your login code...
          {:else}
            send an email to log in...
          {/if}
        </PromptContinue>
      {/if}
    </div>
  </form>
{:else}
  <div class="flex flex-col md:flex-row md:items-center md:gap-4">
    <PromptContinue
      type="button"
      label={auth?.loginLink ? "enter your login code" : "email a login code"}
      {loading}
      {denied}
      {authorize}
      event={"login-link:start"}
      class={"btn-primary"}
    />
  </div>
{/if}
