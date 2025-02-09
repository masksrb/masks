<script>
  import { goto } from "@mateothegreat/svelte5-router";
  import { preventDefault } from "svelte/legacy";
  import { Check, Info, User, Handshake, AlertTriangle } from "lucide-svelte";
  import { gql } from "@urql/svelte";
  import Mutation from "@/components/Mutation.svelte";
  import Alert from "@/components/Alert.svelte";
  import ScopesEditor from "./ScopesEditor.svelte";
  import { TokenFragment } from "@/util.js";
  import TokenResult from "./TokenResult.svelte";

  let result = $state();
  let input = $state({});
  let errors = $state();
  let saved = $state();
  let token = $state();

  let query = gql`
    mutation ($input: TokenInput!) {
      token(input: $input) {
        token {
          ...TokenFragment
        }

        errors
      }
    }

    ${TokenFragment}
  `;

  let gotoToken = (data) => {
    errors = data.errors;

    if (!data.errors.length) {
      saved = true;
      token = data.token;
    }
  };

  let change = (v) => {
    input = { ...input, ...v };
  };

  let validInput = () => {
    if (!input.type) {
      return false;
    }

    if (input.type == "client-token") {
      return input.client;
    }

    if (input.type == "access-token") {
      return input.client && input.actor;
    }

    return false;
  };

  let inputVars = () => {
    let vars = { ...input };

    if (vars.scopes) {
      vars.scopes = vars.scopes.required;
    }

    return vars;
  };

  let reset = () => {
    token = null;
    saved = false;
    input = {};
  };
</script>

{#if saved}
  <Alert type="success" class="mb-6">
    <div class="flex items-center gap-3">
      <span class="grow"
        ><b>Token created!</b> You can copy the secret below...</span
      >
      <button class="btn btn-sm btn-success mx-auto" onclick={reset}
        >add another</button
      >
    </div>
  </Alert>

  <TokenResult {token} open />
{:else}
  <Mutation {query} input={inputVars()} key="token" onmutate={gotoToken}>
    {#snippet children({ mutate, mutating })}
      <form
        action="#"
        onsubmit={preventDefault(mutate)}
        class="w-full flex flex-col gap-3"
      >
        <div class="flex flex-col bg-base-300 px-3 py-1.5 rounded-lg">
          <div class="flex items-center gap-3 p-1.5">
            <div class="grow text-xs md:text-base leading-snug pr-1.5 py-2">
              {#if input.type}
                Token type
              {:else}
                Choose a type...
              {/if}
            </div>

            <button
              onclick={() => change({ type: "client-token" })}
              class={`btn btn-sm ${input.type == "client-token" ? "btn-primary shadow" : "btn-neutral"}`}
              type="button">Client token</button
            >

            <i class="text-xs px-1.5 hidden md:block">or</i>

            <button
              onclick={() => change({ type: "access-token" })}
              class={`btn btn-sm ${input.type == "access-token" ? "btn-primary shadow" : "btn-neutral"}`}
              type="button">Access token</button
            >
          </div>
        </div>
        {#if input.type}
          <div class="flex flex-col gap-3">
            {#if errors?.length}
              <Alert
                class="mt-1.5"
                icon={AlertTriangle}
                type="error"
                {errors}
              />
            {:else}
              <Alert type="info" class="mt-1.5" icon={Info}>
                {#if input.type == "client-token"}
                  Client tokens grant a specific client access to resources.
                {:else if input.type == "access-token"}
                  Access tokens grant an actor access to a client's resources.
                {/if}
              </Alert>
            {/if}

            <label class="input input-lg flex items-center gap-3 flex-grow">
              <input
                type="text"
                class="grow placeholder:opacity-50"
                placeholder="Client ID..."
                bind:value={input.client}
                disabled={!input.type}
              />

              <Handshake />
            </label>

            {#if input.type == "access-token"}
              <label class="input input-lg flex items-center gap-3 flex-grow">
                <input
                  type="text"
                  class="grow placeholder:opacity-50"
                  placeholder="Actor ID..."
                  bind:value={input.actor}
                  disabled={!input.type}
                />

                <User />
              </label>
            {/if}

            {#if validInput()}
              <div class="flex flex-col md:flex-row md:items-center gap-3">
                <label class="input flex items-center gap-3 flex-grow">
                  <span class="text-xs opacity-75 pl-1.5 pr-3"> name </span>
                  <input
                    type="text"
                    class="grow placeholder:opacity-50 w-full"
                    placeholder="optional"
                    bind:value={input.name}
                  />
                </label>

                <label
                  class="input flex items-center gap-3 flex-grow md:max-w-[250px]"
                >
                  <span class="text-xs opacity-75 pl-1.5 pr-3"> lifetime </span>
                  <input
                    type="text"
                    class="grow placeholder:opacity-50 w-full"
                    placeholder="e.g. 1 day"
                    bind:value={input.expiry}
                  />
                </label>
              </div>

              <ScopesEditor required {change} scopes={input.scopes} />
            {/if}

            <div class="flex items-center gap-3 my-1.5">
              <button
                type="submit"
                class="btn btn-lg btn-warning min-w-[90px]"
                disabled={saved || !validInput()}
              >
                {#if !mutating && !saved}
                  save
                {:else}
                  <div class="loading loading-spinner"></div>
                {/if}
              </button>

              {#if validInput()}
                <div
                  class="text-warning font-bold ml-3 flex items-center gap-3"
                >
                  <AlertTriangle class="text-warning" />

                  Keep all tokens secure!
                </div>
              {/if}
            </div>
          </div>
        {/if}
      </form>
    {/snippet}
  </Mutation>
{/if}
