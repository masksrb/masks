<script>
  import _ from "lodash-es";
  import { Check, X, ChevronRight, KeySquare } from "lucide-svelte";

  import Time from "@/components/Time.svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import { getContext } from "svelte";

  let { auth, authorize, prompt, ...props } = $props();

  let actor = $derived(auth?.actor);
  let passwordChange = $state({});

  let changingPassword = () => {
    passwordChange = { ...passwordChange, changing: true };
  };

  let cancelPasswordChange = () => {
    passwordChange = {};
  };

  let passwordChanged = () => {
    cancelPasswordChange();
    passwordChange.changed = true;
  };

  let changePassword = () => {
    authorize({
      event: prompt.verification("password:change", {
        done: passwordChanged,
      }),
      updates: {
        value: passwordChange.value,
      },
    });
  };
</script>

<div class="cols-1.5 w-full grow">
  {#if passwordChange.changing}
    {#if actor.passwordChangeable}
      <div class="grow rows gap-1 w-full">
        <PasswordInput
          autofocus={getContext("autofocus")}
          bind:value={passwordChange.value}
          bind:valid={passwordChange.valueValid}
          placeholder={actor.password
            ? "Enter a new password"
            : "Add a password"}
          class="grow min-w-0 w-full"
          {auth}
        >
          {#snippet end()}
            {#if passwordChange.value}
              <button
                disabled={!passwordChange.valueValid}
                type="button"
                class="btn btn-primary btn-xs -mr-1.5"
                onclick={changePassword}
              >
                change
              </button>
            {:else}
              <button
                type="button"
                class="btn btn-sm -mr-1.5 btn-square text-error"
                onclick={cancelPasswordChange}
              >
                <X size="14" />
              </button>
            {/if}
          {/snippet}
        </PasswordInput>
      </div>
    {/if}
  {:else}
    <div
      class={`bg-base-100 rounded-lg input w-full cols-3 bg-opacity-50 shadow`}
    >
      {#if passwordChange.changed}
        <Check size="18" class="mr-0.5 text-success" />
      {:else}
        <KeySquare size="18" class="mr-0.5 text-accent" />
      {/if}

      <div class="grow">
        <div
          class={`${actor.passwordChangeable ? "text-sm" : "text-sm"} truncate`}
        >
          {#if actor.passwordChangedAt}
            {#if passwordChange.changed}
              <b class="text-success">Password changed</b>
            {:else}
              Password changed
            {/if}
            {#key actor.passwordChangedAt}
              <b>
                <Time
                  style="long"
                  relative
                  timestamp={actor.passwordChangedAt}
                />...
              </b>
            {/key}
          {:else if !actor.password}
            Password <b>not set</b>...
          {:else}
            Password <b>never</b> changed...
          {/if}
        </div>

        {#if !actor.passwordChangeable}
          <div class="text-xs opacity-75 truncate">
            Wait a bit to change it again...
          </div>
        {/if}
      </div>

      <button
        disabled={!actor.passwordChangeable}
        type="button"
        class="btn btn-xs btn-ghost -mr-1.5"
        onclick={changingPassword}
      >
        {actor.password ? "change" : "add"}
      </button>
    </div>
  {/if}
</div>
