<script>
  import _ from "lodash-es";

  import { Send, Info, Mail } from "lucide-svelte";

  import Time from "@/components/Time.svelte";
  import Alert from "@/components/Alert.svelte";
  import Dropdown from "@/components/Dropdown.svelte";
  import CodeInput from "@/components/CodeInput.svelte";

  let { authorize, authorizing, ...props } = $props();

  let auth = $state();
  let emails = $state();
  let email = $state();
  let verifying = $state();
  let code = $state([]);
  let value = $state("");
  let denied = $state();

  let changeEmail = (e) => {
    return () => {
      email = e;
      verifying = e.verifyLink;
    };
  };

  let verifyEmail = () => {
    authorize({
      event: "email:notify",
      updates: {
        email: { address: email.address },
      },
    }).then(updateAuth);
  };

  let verifyCode = (code) => {
    authorize({
      sudo: true,
      event: "email:verify",
      updates: {
        email: {
          address: email.address,
          code,
        },
      },
    }).then((r) => {
      auth = r.auth;
    });
  };

  let updateAuth = (v) => {
    auth = v.auth;
    emails = auth.actor.loginEmails;
    verifying = emails.find((e) => e.verifyLink);
    email = verifying || emails[0];
  };

  updateAuth(props);
</script>

{#if authorizing}
  <Alert type="info">
    <div class="rows-3">
      <div>
        <Dropdown value={email}>
          {#snippet summary({ value })}
            <summary
              class="cols-1.5 btn btn-xs bg-info-content border-info-content text-info pl-1.5 rounded"
            >
              <Mail size="12" />

              <div class="max-w-[175px]">
                {value?.address}
              </div>
            </summary>
          {/snippet}

          {#snippet dropdown({ value, setValue })}
            <div>
              {#if emails?.length > 1}
                <div class="m-1.5 rows gap-1.5">
                  {#each emails as e}
                    <button
                      onclick={() => setValue(e, changeEmail(e))}
                      class={`w-full btn btn-xs ${e.address == value.address ? "btn-info" : "btn-info btn-outline"}`}
                    >
                      <span class="truncate">{e.address}</span>
                    </button>
                  {/each}
                </div>
              {:else}
                <div
                  class="text-xs whitespace-nowrap flex items-center gap-1.5 px-3 py-1.5"
                >
                  <Info size="12" />
                  <span>
                    You added this email <Time timestamp={email?.createdAt} />.
                  </span>
                </div>
              {/if}
            </div>
          {/snippet}
        </Dropdown>
      </div>

      {#if verifying}
        <div class="rows-1.5 mb-1.5">
          <div class="cols-3 dark:text-info text-info-content mb-1.5">
            <div class="text-lg">
              <b>Check your email</b> for a 7-character code and enter it below...
            </div>

            <Send size="30" class="dim" />
          </div>

          <CodeInput
            {auth}
            bind:code
            bind:value
            verify={verifyCode}
            class="border-info text-info-content bg-info bg-opacity-75 input-lg placeholder:text-info text-2xl"
          />
        </div>
      {:else}
        <button class="btn btn-info btn-lg mb-1.5" onclick={verifyEmail}>
          <div class="cols-3">
            <Send size="18" />
            Email a verification code
          </div>
        </button>
      {/if}
    </div>
  </Alert>
{/if}
