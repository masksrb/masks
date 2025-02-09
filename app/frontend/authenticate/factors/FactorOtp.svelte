<script>
  import _ from "lodash-es";
  import * as OTPAuth from "otpauth";
  import { qr } from "@svelte-put/qr/svg";

  import {
    X,
    Trash2 as Trash,
    QrCode as Icon,
    ChevronDown,
    Info,
  } from "lucide-svelte";

  import Card from "@/components/Card.svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import CodeInput from "@/components/CodeInput.svelte";
  import Dropdown from "@/components/Dropdown.svelte";
  import Time from "@/components/Time.svelte";
  import Alert from "@/components/Alert.svelte";
  import CopyButton from "@/components/CopyButton.svelte";

  let { prompt, authorizing, authorize, loading, ...props } = $props();

  let auth = $state(props.auth);
  let adding = $state();
  let verifying = $state();
  let code = $state();
  let value = $state();
  let secret = $state();
  let secrets = $state();
  let empty = $derived(!secrets?.length);

  let toggleAdding = (v) => {
    return () => {
      code = [];
      value = "";
      adding = v;
    };
  };

  let resetOTP = () => {
    adding = false;
    code = [];
    value = null;

    return new OTPAuth.TOTP({
      issuer: auth.settings.name,
      label: auth.actor.identifier,
      secret: new OTPAuth.Secret(),
    });
  };

  let otp = $state(resetOTP());

  let updateAuth = (r) => {
    auth = r.auth;
    secrets = auth.actor.otpSecrets;

    if (authorizing) {
      secret = secrets[0];
    }
  };

  updateAuth(prompt);

  let debounceName = _.debounce((id, name) => {
    authorize({ event: "otp:name", updates: { otp: { id, name } } });
  }, 500);

  let deleteOtp = (otpSecret) => {
    return () => {
      code = [];
      value = "";

      authorize({
        event: prompt.verification("otp:delete", {
          done: updateAuth,
        }),
        updates: { delete: { id: otpSecret.id } },
      });
    };
  };

  let updateName = (id) => {
    return (e) => {
      debounceName(id, e.target.value);
    };
  };

  let debounceAdd = (secret, inputCode) => {
    if (verifying) {
      return;
    }

    verifying = true;

    return authorize({
      event: prompt.verification("otp:create", {
        done: (result) => {
          verifying = false;

          if (!result?.warnings?.length) {
            otp = resetOTP();
            code = [];
            value = "";
          } else {
            denied = true;
          }

          updateAuth(result);
        },
      }),
      updates: { create: { secret, code: inputCode } },
    });
  };

  let denied = $state();

  let debounceVerify = _.debounce((secret, inputCode) => {
    if (!secret.id || !inputCode) {
      return;
    }

    authorize({
      sudo: true,
      event: "otp:verify",
      updates: { otp: { id: secret.id, code: inputCode } },
    }).then((result) => {
      if (result?.warnings?.length) {
        verifying = false;
        denied = true;
      }

      updateAuth(result);
    });
  }, 150);

  let dropdown;

  let chooseSecret = (s) => {
    return (e) => {
      e.preventDefault();
      e.stopPropagation();

      secret = s;

      if (dropdown) {
        dropdown.open = false;
      }
    };
  };
</script>

{#if authorizing}
  <Alert type="secondary">
    <div class="flex items-center gap-1.5 mb-1.5">
      <Dropdown value={secret} dropdownClass="mt-1">
        {#snippet summary()}
          <summary class="btn btn-xs btn-neutral">
            <div class="truncate max-w-[175px]">
              {#if secret.name}
                <span class="truncate">{secret.name}</span>
              {:else}
                <span class="truncate opacity-75 italic">unnamed</span>
              {/if}
            </div>

            {#if secrets?.length > 1}
              <ChevronDown size="16" class="opacity-75" />
            {/if}
          </summary>
        {/snippet}

        {#snippet dropdown()}
          <div class="box py-1.5">
            {#if secrets?.length > 1}
              <ul class="">
                <li
                  class="py-0.5 text-xs opacity-75 whitespace-nowrap pl-1.5 mb-1.5"
                >
                  Choose another authenticator...
                </li>
                {#each secrets as s}
                  <li class="py-0.5">
                    <button
                      class={`${s == secret ? "btn-outline" : ""} btn btn-xs max-w-[200px] w-auto overflow-hidden`}
                      type="button"
                      onclick={chooseSecret(s)}
                    >
                      {#if s.name}
                        <span class="truncate">{s.name}</span>
                      {:else}
                        <span class="truncate opacity-75 italic">unnamed</span>
                      {/if}
                    </button>
                  </li>
                {/each}
              </ul>
            {:else}
              <div
                class="text-xs whitespace-nowrap flex items-center gap-1.5 text-neutral-content"
              >
                <Info size="16" />
                <span class="">
                  You added this authenticator <Time
                    timestamp={secret.createdAt}
                  />.
                </span>
              </div>
            {/if}
          </div>
        {/snippet}
      </Dropdown>

      {#if denied}
        <p class="grow text-right text-xs text-error">
          Invalid code. try again...
        </p>
      {:else}
        <p class="grow text-right text-xs opacity-75 md:block hidden">
          enter the 6-character code...
        </p>
      {/if}
    </div>

    <CodeInput
      {auth}
      length={6}
      type="numeric"
      class="input-secondary bg-transparent placeholder:text-secondary placeholder:opacity-25 input-lg text-xl mb-1.5"
      bind:code
      bind:value
      verify={(val) => debounceVerify(secret, val)}
    />
  </Alert>
{:else}
  <Card>
    <div class="flex items-center gap-1.5 py-1">
      <Icon size="14" />

      <div class="grow">
        <div class="label-bold">Authenticator app</div>
      </div>
    </div>

    {#if empty && !verifying && !adding}
      <div class="text-sm opacity-75 mb-3">
        Use one-time passwords from an authenticator app.
      </div>
    {/if}

    <div class="flex flex-col gap-1.5 my-1.5">
      {#key secrets?.length}
        {#each secrets as otpSecret}
          <div class="flex items-center gap-3">
            <label
              class="grow flex items-center gap-3 w-full input input-sm px-1.5 h-[35px]"
            >
              <input
                class="w-full pl-1.5 text-base dark:text-white text-black placeholder:text-sm placeholder:text-warning"
                placeholder="Enter a name for this authenticator..."
                value={otpSecret.name}
                oninput={updateName(otpSecret.id)}
                disabled={loading}
              />
              <span
                class="text-xs whitespace-nowrap text-base-content opacity-75"
                ><Time ago="old" timestamp={otpSecret.createdAt} /></span
              >
              <button
                type="button"
                class="btn btn-xs text-error m-0 p-0 px-1"
                onclick={deleteOtp(otpSecret)}
              >
                <Trash size="14" />
              </button>
            </label>
          </div>
        {/each}
      {/key}
    </div>

    {#if adding}
      <div class="mb-3 bg-base-100 p-3 px-4 rounded-lg">
        <div class="flex items-start gap-3 mb-3">
          <p class="text-sm">
            <b>Step one:</b> Scan the following QR code in your authenticator app.
            You can also enter the secret manually:
          </p>

          {#if !empty}
            <button
              type="button"
              onclick={toggleAdding(false)}
              class="btn btn-sm px-1"><X /></button
            >
          {/if}
        </div>

        <svg
          class="mb-1.5 w-full h-full max-w-[250px] mx-auto rounded"
          use:qr={{
            data: otp.toString(),
            shape: "circle",
          }}
        />

        <div class="max-w-[250px] mx-auto">
          <PasswordInput
            disabled
            value={otp.secret.base32}
            class="input-sm ml-0"
          >
            {#snippet end()}
              <CopyButton value={otp.secret.base32} />
            {/snippet}
          </PasswordInput>
        </div>

        <div class="divider mb-1.5 mt-0"></div>

        <p class="text-sm mb-1.5">
          <b>Step two:</b>
          Enter the 6-digit code generated by your authenticator app:
        </p>

        {#key otp.secret.base32}
          <CodeInput
            {auth}
            type="numeric"
            length={6}
            bind:code
            bind:value
            verify={(val) => debounceAdd(otp.secret.base32, val)}
          />
        {/key}
      </div>
    {:else}
      <button
        type="button"
        class="btn btn-sm w-full"
        onclick={toggleAdding(true)}
      >
        {#if empty}
          Add an authenticator
        {:else}
          Add another authenticator
        {/if}
      </button>
    {/if}
  </Card>
{/if}
