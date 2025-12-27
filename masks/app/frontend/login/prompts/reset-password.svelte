<script>
import { Info } from "lucide-svelte";
import Time from "@/components/Time.svelte";
import Alert from "@/components/Alert.svelte";
import PromptHeader from "../shared/PromptHeader.svelte";
import PromptContinue from "../shared/PromptContinue.svelte";
import PromptFocused from "../shared/PromptFocused.svelte";
import PasswordInput from "@/components/PasswordInput.svelte";

let { auth, loading, authorize } = $props();

let password = $state();
let valid = $state();
let changed = $state(!auth.actor.passwordChangeable);
let denied = $state();

let changePassword = () => {
  if (!valid) {
    return;
  }

  authorize({
    event: "password:reset",
    updates: { reset: password },
  }).then((result) => {
    denied = result?.warnings?.includes("invalid-password");
    changed = result?.warnings?.includes("changed-password");
  });
};
</script>

<PromptFocused {auth}>
  <PromptHeader
    heading={changed ? "Password changed!" : "Reset your password?"}
    class="text-center"
  />

  {#if !changed}
    <Alert type="accent" class="pr-5" icon={Info}>
      {#if auth?.actor?.passwordChangedAt}
        You last changed your password <Time
          timestamp={auth.actor.passwordChangedAt}
        />.
      {:else if auth?.actor?.password}
        You have never changed your password.
      {:else}
        You do not have an existing password.
      {/if}
    </Alert>

    <PasswordInput
      {auth}
      class="input-lg"
      placeholder="Enter a new password"
      bind:value={password}
      bind:valid
      disabled={changed}
    />
  {/if}

  <PromptContinue
    {authorize}
    onclick={!changed ? changePassword : null}
    event={`password:skip-reset`}
    label={changed ? "Continue" : "Change"}
    {loading}
    {denied}
    disabled={!changed && !valid}
    class={`${changed ? "mt-3 btn-success" : "btn-accent"} !min-w-0 px-1.5`}
  />

  <div class="cols-3 mx-auto justify-center">
    {#if changed}
      <span class="opacity-75 text-lg mx-1.5"> or </span>
    {/if}

    <PromptContinue
      {authorize}
      event="password:skip-reset"
      updates={{ profile: true }}
      label={`edit your profile`}
      class="!btn-link !min-w-0 px-0 !text-base-content dim"
    />

    {#if !changed}
      <span class="opacity-75 text-lg mx-1.5"> or </span>

      <PromptContinue
        {authorize}
        event="password:skip-reset"
        label={`skip...`}
        class="!btn-link !min-w-0 px-0 !text-base-content dim"
      />
    {/if}
  </div>
</PromptFocused>
