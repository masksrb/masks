<script>
  import _ from "lodash-es";

  import {
    X,
    QrCode,
    KeySquare,
    EllipsisVertical,
    MessageSquare,
    Fingerprint,
    Mail,
    History,
    ChevronLeft,
  } from "lucide-svelte";

  import FactorWebauthn from "./FactorWebauthn.svelte";
  import FactorOtp from "./FactorOtp.svelte";
  import FactorPhoneNumber from "./FactorPhoneNumber.svelte";
  import FactorBackupCodes from "./FactorBackupCodes.svelte";
  import FactorPassword from "./FactorPassword.svelte";
  import FactorEmail from "./FactorEmail.svelte";
  import Dropdown from "@/components/Dropdown.svelte";
  import PromptHeader from "../shared/PromptHeader.svelte";
  import PromptIdentifier from "../shared/PromptIdentifier.svelte";

  let { prompt, ...props } = $props();

  let computeFactors = (prompt) => {
    let auth = prompt.auth;

    if (!auth?.client || !auth?.actor) {
      return {};
    }

    let verifyFirst = props?.allow?.first || prompt.verifying?.first;
    let verifySecond = props?.allow?.second || prompt.verifying?.second;
    let verifyBackupCodes =
      props.allow?.backupCodes || prompt.verifying?.backupCodes;

    let emails =
      verifyFirst && auth.client.allowEmails && auth.actor.loginEmails?.length;
    let passwords =
      verifyFirst && auth.client.allowPasswords && auth.actor.password;
    let webauthn =
      verifySecond &&
      auth.client.allowWebauthn &&
      auth.actor.hardwareKeys?.length;
    let phones =
      verifySecond && auth.client.allowPhones && auth.actor.phones?.length;
    let otp =
      verifySecond && auth.client.allowOtp && auth.actor.otpSecrets?.length;
    let backupCodes =
      verifyBackupCodes &&
      auth.client.allowBackupCodes &&
      auth?.actor?.savedBackupCodesAt;

    let factors = [
      passwords
        ? {
            key: "password",
            component: FactorPassword,
            label: "Enter your password",
            icon: KeySquare,
          }
        : null,
      emails
        ? {
            key: "email",
            component: FactorEmail,
            label: "Email a verification code",
            icon: Mail,
          }
        : null,
      webauthn
        ? {
            key: "webauthn",
            component: FactorWebauthn,
            label: "Verify your security key",
            second: true,
            icon: Fingerprint,
          }
        : null,
      phones
        ? {
            key: "phone",
            component: FactorPhoneNumber,
            label: "Send a code to your phone",
            second: true,
            icon: MessageSquare,
          }
        : null,
      otp
        ? {
            key: "otp",
            component: FactorOtp,
            label: "Use your authenticator app",
            second: true,
            icon: QrCode,
          }
        : null,
      backupCodes
        ? {
            key: "backup",
            label: "Enter a backup code",
            component: FactorBackupCodes,
            second: true,
            icon: History,
          }
        : null,
    ].filter(Boolean);

    let selected;

    if (verifySecond) {
      selected = factors.find((f) => f.second);
    }

    selected = selected || factors[0];

    let enabled = Object.fromEntries(
      factors.map((f) => {
        return [f.key, f];
      })
    );

    return {
      enabled,
      selected,
      switchOne: factors.length == 2,
      backupCodes,
    };
  };

  let factors = $derived.by(() => computeFactors(prompt));
  let factor = $state(factors.selected);
  let Factor = $derived(factor?.component);
  let previousFactor = $state();
  let changing = $state();

  let toggleChanging = () => {
    changing = !changing;
  };

  let switchFactor = (v, cb) => {
    return (e) => {
      e.preventDefault();
      e.stopPropagation();

      changing = false;
      previousFactor = factor;
      factor = v;

      cb(v);
    };
  };

  let lockedTab = $state();
  let setLocked = (v) => {
    lockedTab = v;
  };

  let toggleFactor = () => {
    if (Object.values(factors.enabled).length === 2) {
      factor = alternateFactor();
    }
  };

  let alternateFactor = () => {
    return Object.values(factors.enabled).find((f) => f.key !== factor.key);
  };
</script>

{#snippet subheading()}
  to {prompt.verifying?.to
    ? _.template(prompt.verifying.to)(prompt.verifying)
    : "continue"}
{/snippet}

<PromptHeader
  client={prompt.auth.client}
  heading={changing ? "Enter a secondary credential" : factor.label}
  class="mb-6"
  subheading={props.subheading || subheading}
  logo={props.cancel}
/>

{#if props.identifier}
  <PromptIdentifier auth={prompt.auth} class="mb-3" />
{/if}

{#if changing}
  <div class="w-full rows-3 box bg-base-100 shadow">
    <button class={`btn btn-neutral cols-3`} onclick={switchFactor(factor)}>
      <span class="text-lg grow text-left">{factor.label}</span>
      <div>
        <ChevronLeft size="18" class="dim" />
      </div>
    </button>

    {#each Object.values(factors.enabled) as f}
      {#if f.key != factor.key}
        {@const Icon = f.icon}
        <button
          class={`btn cols-3 btn-outline ${f.class}`}
          onclick={switchFactor(f)}
        >
          <span class="text-lg grow text-left">{f.label}</span>
          <div>
            <Icon size="18" class="dim" />
          </div>
        </button>
      {/if}
    {/each}
  </div>
{:else}
  <div class="mb-3">
    <Factor {...props} {prompt} authorizing {setLocked} />
  </div>

  {#if factors.switchOne}
    <div class="cols-1.5 justify-center">
      <span class="label-sm">or</span>
      <button class="btn btn-sm btn-ghost" onclick={toggleFactor}
        >{alternateFactor().label}</button
      >
    </div>
  {:else}
    <Dropdown
      value={factor}
      class="w-full dropdown-top"
      dropdownClass="w-full rows justify-center mb-3"
    >
      {#snippet summary({ value, open })}
        <summary class="w-full">
          <div class="cols-1.5 justify-center w-full">
            <span class="label-sm">or</span>
            <span class="btn btn-sm btn-ghost min-w-[150px]">
              {open ? "cancel selection" : "choose another option..."}
            </span>
          </div>
        </summary>
      {/snippet}

      {#snippet dropdown({ value, setValue })}
        <div class="w-full rows-3 box bg-gray-800 dark:bg-base-300 shadow-2xl">
          <div class="text-neutral-content pl-3 dim">
            Select another credential...
          </div>
          {#each Object.values(factors.enabled).reverse() as f}
            {#if f.key != factor.key}
              {@const Icon = f.icon}
              <button
                class={`btn whitespace-nowrap cols-3 btn-neutral ${f.class}`}
                onclick={switchFactor(f, setValue)}
              >
                <span class="text-lg grow text-left truncate">{f.label}</span>
                <div class="hidden md:block">
                  <Icon size="18" class="dim" />
                </div>
              </button>
            {/if}
          {/each}
        </div>
      {/snippet}
    </Dropdown>
  {/if}
{/if}
