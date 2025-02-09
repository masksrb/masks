<script>
  import { MailCheck, MailOpen, MailPlus, Trash2 } from "lucide-svelte";

  import Time from "@/components/Time.svelte";
  import CodeInput from "@/components/CodeInput.svelte";

  let { prompt, authorize, email, btnClass, inputClass, cls } = $props();

  let auth = $derived(prompt);
  let newEmail = $state();
  let code = $state();
  let value = $state();
  let verifying = $state();

  let isTooMany = (auth) => auth?.warnings?.includes(`email:limit`);
  let isWarning = (auth) => auth?.warnings?.includes(`email:invalid`);
  let tooMany = $derived(isTooMany(auth));
  let warning = $derived(isWarning(auth));

  let deletedEmail = () => {};

  let deleteEmail = () => {
    authorize({
      event: prompt.verification("email:delete", {
        done: deletedEmail,
        email: email.address,
      }),
      updates: { delete: { address: email.address } },
    });
  };

  let verifyCode = (code) => {
    authorize({
      event: `email:verify`,
      updates: { email: { code, address: email.address } },
    });
  };

  let verifyEmail = () => {
    if (email?.verifyLink) {
      verifying = !verifying;

      return;
    }

    authorize({
      event: "email:notify",
      updates: { email: { address: email.address } },
    });
  };

  let addedEmail = (r) => {
    prompt = r;
    newEmail = null;
  };

  let addEmail = (e) => {
    e.preventDefault();
    e.stopPropagation();

    authorize({
      event: prompt.verification("email:create", {
        done: addedEmail,
        email: newEmail,
      }),
      updates: { create: { address: newEmail } },
    });
  };
</script>

{#if email}
  <div>
    <div
      class={[
        "cols-1.5 bg-base-100",
        "shadow p-2 px-3",
        verifying ? "rounded-t-lg" : "rounded-lg",
      ].join(" ")}
    >
      <div class="grow rows gap-0.5 pl-1.5">
        <span
          class="font-mono grow text-sm dark:text-white text-black truncate"
        >
          {email.address}
        </span>
        <span class="text-xs items-start cols-1.5">
          {#if email.verifyLink}
            <MailOpen size="12" class="text-accent" />
            <span class="text-xs italic">Check your email...</span>
          {:else if email.verifiedAt}
            <MailCheck size="12" class="text-success" /> <b>verified</b>
            <Time timestamp={email.verifiedAt} />
          {:else}
            added <Time timestamp={email.createdAt} />
          {/if}
        </span>
      </div>

      {#if !email?.verifiedAt && !email?.verifyLink}
        <button type="button" class={`btn w-auto btn-xs`} onclick={verifyEmail}
          >verify</button
        >
      {:else if email.verifyLink}
        <button
          class={`btn btn-xs btn-outline ${verifying ? "btn-error" : "btn-accent"}`}
          onclick={() => (verifying = !verifying)}
        >
          {verifying ? "cancel" : "enter code"}
        </button>
      {/if}

      <button
        disabled={!email.deletable}
        type="button"
        class="btn btn-square btn-ghost text-error btn-xs"
        onclick={deleteEmail}
      >
        <Trash2 size="14" />
      </button>
    </div>

    {#if email.verifyLink}
      {#if verifying}
        <div class="flex flex-col">
          <div
            class="text-sm text-left border-x dark:border-neutral border-neutral-content border-dashed px-3 py-3 bg-base-200"
          >
            <div class="pl-1.5">
              Check your email for a 7-character verification code. Enter it
              below to verify your email address...
            </div>
          </div>
          <CodeInput
            {auth}
            bind:code
            bind:value
            verify={verifyCode}
            class="rounded-t-none"
          />
        </div>
      {/if}
    {/if}
  </div>
{:else}
  <form onsubmit={addEmail}>
    <div class={[warning ? "animate-denied" : ""].join(" ")}>
      <div class={`flex items-center gap-1.5 grow ${cls}`}>
        <label
          class={`input input-ghost flex items-center gap-3 grow ${inputClass} input-bordered my-0 min-w-0 w-0`}
        >
          <MailPlus size="20" class="dim" />

          <input
            class={warning || tooMany
              ? "placeholder:text-error w-full"
              : "w-full"}
            placeholder={tooMany
              ? "You cannot add any more emails..."
              : warning
                ? "Email is already taken or invalid..."
                : "Enter a new email address..."}
            bind:value={newEmail}
            disabled={tooMany}
          />

          <button
            type="submit"
            class={`btn btn-xs btn-info ${btnClass} ${warning ? "btn-warning" : ""} -mr-1.5`}
            disabled={tooMany || !newEmail?.includes("@")}
          >
            add email
          </button>
        </label>
      </div>
    </div>
  </form>
{/if}
