<script>
  import _ from "lodash-es";

  import {
    Trash2 as Trash,
    MessageSquare,
    AlertTriangle,
    ChevronDown,
  } from "lucide-svelte";

  import PhoneInput from "@/components/PhoneInput.svelte";
  import CodeInput from "@/components/CodeInput.svelte";
  import Dropdown from "@/components/Dropdown.svelte";
  import Time from "@/components/Time.svelte";
  import Alert from "@/components/Alert.svelte";
  import Card from "@/components/Card.svelte";
  import parsePhoneNumber from "libphonenumber-js";

  let { prompt, authorize, authorizing, loading, setLocked, ...props } =
    $props();

  let auth = $state();
  let invalidPhone = $state();
  let invalidCode = $state();
  let phones = $derived(auth?.actor?.phones);
  let empty = $derived(!phones?.length);
  let phone = $state();
  let adding = $state();

  let addPhone = () => {
    adding = true;
  };

  let updateAuth = (result) => {
    auth = result.auth;

    if (!phone) {
      phone = authorizing && phones?.length ? phones[0] : {};
    }

    invalidPhone = result?.warnings?.includes("invalid-phone");
    invalidCode = result?.warnings?.includes(`invalid-code:${phone.code}`);
  };

  updateAuth(prompt);

  let deletePhone = (p) => {
    return () => {
      authorize({
        event: prompt.verification("phone:delete", {
          done: updateAuth,
        }),
        updates: { phone: { number: p.number } },
      });
    };
  };

  let createPhone = () => {
    let updates = { create: _.pick(phone, ["number", "code"]) };
    let event = prompt.verification("phone:create", {
      done: (result) => {
        updateAuth(result);

        if (!invalidCode) {
          phone = {};
        }
      },
    });

    authorize({ event, updates });
  };

  let verifyCode = () => {
    let event = "phone:verify";
    let updates = { phone: _.pick(phone, ["number", "code"]) };

    authorize({ sudo: true, event, updates }).then(updateAuth);
  };

  let sendCode = (e) => {
    e.preventDefault();
    e.stopPropagation();

    let event = "phone:send";
    let updates = _.pick(phone, ["number"]);

    if (authorizing) {
      updates = { phone: updates };
    } else {
      updates = { create: updates };
    }

    authorize({ event, updates }).then((result) => {
      updateAuth(result);

      if (!invalidPhone) {
        phone.verifying = true;
      }
    });
  };

  let cancelVerify = () => {
    phone.verifying = false;
    setLocked(false);
  };

  let formatPhone = (phone) => {
    return parsePhoneNumber(phone?.number)?.formatInternational();
  };
</script>

{#if authorizing}
  <Alert type="secondary">
    <Dropdown value={phone}>
      {#snippet summary({ value })}
        <summary class="btn btn-xs btn-neutral mb-1.5">
          <span>
            {formatPhone(value)}
          </span>

          {#if phone.verifying}
            <p class="text-xs whitespace-nowrap opacity-75">
              enter the code...
            </p>
          {/if}

          {#if phones?.length > 1}
            <ChevronDown size="16" />
          {/if}
        </summary>
      {/snippet}

      {#snippet dropdown({ setValue, value })}
        <div class="box py-1.5">
          {#if phones?.length > 1}
            <div class="flex flex-col space-y-1.5 my-1.5">
              <div class="text-xs whitespace-nowrap mb-1.5">
                Choose a phone number...
              </div>
              {#each phones as p}
                <button
                  type="button"
                  class={`btn btn-sm whitespace-nowrap ${p == value ? "text-secondary" : ""}`}
                  onclick={setValue(p, (v) => (phone = v))}
                >
                  {formatPhone(p)}
                </button>
              {/each}
            </div>
          {:else}
            <span
              class="whitespace-nowrap opacity-75 text-xs block text-neutral-content"
            >
              Phone added <Time timestamp={phone?.createdAt} />
            </span>
          {/if}
        </div>
      {/snippet}
    </Dropdown>

    {#if phone.verifying}
      <div class="">
        <CodeInput
          {auth}
          verify={verifyCode}
          length={6}
          disabled={loading}
          bind:value={phone.code}
          class="input-lg bg-transparent input-secondary placeholder:text-secondary placeholder:opacity-25 mb-1.5"
          type="numeric"
        />
      </div>

      <div class="text-center text-sm opacity-75">
        or <button class="underline" onclick={cancelVerify} type="button"
          >cancel</button
        >
      </div>
    {:else}
      <button class="btn btn-secondary w-full btn-lg mb-1.5" onclick={sendCode}>
        <div class="flex items-center gap-3 text-left">
          <MessageSquare size="16" /> Send verification code
        </div>
      </button>
    {/if}
  </Alert>
{:else}
  <Card>
    <div class="flex items-center gap-1.5 my-1">
      <MessageSquare size="14" />

      <div class="label-bold">Phone & Text</div>
    </div>

    {#if empty && !phone.verifying}
      <div class="text-sm opacity-75 mb-3">
        Receive one-time codes to your phone number.
      </div>
    {/if}

    {#if invalidCode || invalidPhone}
      <Alert type="warn" icon={AlertTriangle} class="mb-1.5">
        {#if invalidPhone}
          Invalid phone number...
        {:else}
          Invalid verification code...
        {/if}
      </Alert>
    {/if}

    <div class="flex flex-col gap-1.5">
      {#if !empty}
        {#each phones as phone}
          <div>
            <div class="flex items-center gap-3">
              <PhoneInput disabled value={phone.number}>
                <span
                  class="text-xs whitespace-nowrap text-base-content opacity-75"
                  ><Time ago="old" timestamp={phone.createdAt} /></span
                >

                <button
                  type="button"
                  class="btn btn-xs text-error m-0 p-0 px-1"
                  onclick={deletePhone(phone)}
                >
                  <Trash size="14" />
                </button>
              </PhoneInput>
            </div>
          </div>
        {/each}
      {/if}

      {#if phone.verifying}
        <div class="bg-base-100 p-3 py-1.5 rounded-lg pb-3">
          <p class="text-sm mt-1.5 mb-3 pl-1.5">
            Enter the code that was just sent to <b>{formatPhone(phone)}</b>...
          </p>

          <CodeInput
            {auth}
            verify={createPhone}
            disabled={loading}
            bind:value={phone.code}
            length={6}
            type="numeric"
          />
        </div>
      {:else if !empty && !adding}
        <button class={"btn btn-sm w-full"} onclick={addPhone}>
          Add another phone
        </button>
      {:else}
        <div class="flex items-center gap-3">
          <PhoneInput
            bind:value={phone.number}
            bind:valid={phone.valid}
            selectedCountry={auth?.settings?.region}
            placeholder={empty
              ? "Add your phone number..."
              : "Add another phone number..."}
          >
            <button
              type="button"
              class={!phone.number
                ? "hidden"
                : phone.valid
                  ? "btn btn-sm btn-success"
                  : "btn btn-sm"}
              disabled={!phone.valid}
              onclick={sendCode}
            >
              verify
            </button>
          </PhoneInput>
        </div>
      {/if}
    </div>
  </Card>
{/if}
