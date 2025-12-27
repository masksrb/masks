<script>
import _ from "lodash-es";

import { LockKeyholeOpen } from "lucide-svelte";

import PasswordInput from "@/components/PasswordInput.svelte";
import Alert from "@/components/Alert.svelte";
import PromptContinue from "../shared/PromptContinue.svelte";

import { getContext } from "svelte";

let { auth, authorize, authorizing, ...props } = $props();

let password = $state();
let validPassword = $state();
let denied = $state();
let verify = (e) => {
  e.preventDefault();
  e.stopPropagation();

  authorize({
    sudo: true,
    event: "password",
    updates: { password },
  }).then((r) => {
    denied = r.auth?.warnings?.length;
  });
};
</script>

<form onsubmit={verify}>
  {#if authorizing}
    <Alert type="accent">
      <div class="rows-3 grow py-1.5">
        <PasswordInput
          auth={props.prompt.auth}
          bind:value={password}
          bind:valid={validPassword}
          placeholder={"Current password"}
          class={`input-lg input-ghost grow ${denied ? "!input-warning" : ""}`}
          inputClass="dark:placeholder:text-accent placeholder:text-accent-content placeholder:opacity-50"
          autofocus={getContext("autofocus")}
        />

        <PromptContinue
          type="submit"
          {denied}
          class={denied ? "btn-warning" : "btn-accent"}
          label={"Verify"}
          icon={LockKeyholeOpen}
          disabled={!password || !validPassword}
        />
      </div>
    </Alert>
  {/if}
</form>
