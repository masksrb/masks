<script>
  import _ from "lodash-es";
  import {
    X,
    Check,
    UserRoundPen,
    UserRoundCheck,
    CornerLeftUp,
    LockKeyhole,
    LockKeyholeOpen,
    LogOut,
    LogIn,
    ChevronLeft,
  } from "lucide-svelte";

  import Time from "@/components/Time.svelte";
  import Alert from "@/components/Alert.svelte";
  import OnboardEmail from "../shared/OnboardEmail.svelte";
  import Identicon from "@/components/Identicon.svelte";
  import EditableImage from "@/components/EditableImage.svelte";
  import SecondFactor from "../profile/SecondFactor.svelte";
  import ChangePassword from "../profile/ChangePassword.svelte";
  import SingleSignOn from "../profile/SingleSignOn.svelte";
  import Devices from "../profile/Devices.svelte";
  import PromptContinue from "../shared/PromptContinue.svelte";

  let { canContinue, ...props } = $props();
  let { auth, authorize, prompt, startOver } = $derived(props);
  let loading = $derived(props.loading);
  let actor = $derived(auth?.actor);
  let avatarUploaded = $derived(actor.avatar);
  let nicknameEnabled = $derived(auth?.client?.allowNicknames);
  let singleSignOns = $derived(prompt.ssoProviders());
  let nameUpdated = $state(false);
  let nameTimeout;
  let extras = $derived(auth?.extras);
  let require2FA = $derived(extras?.secondFactorRequired);
  let defaultState = () => {
    return require2FA ? "second-factor" : null;
  };
  let pane = $state(defaultState());

  $effect(() => {
    if (
      !require2FA &&
      (!extras?.secondFactorEnabled || !auth.client.allowProfiles)
    ) {
      canContinue("profile:verify");
    }
  });

  let uploadAvatar = (file) => {
    authorize({
      event: "avatar:upload",
      uploads: true,
      upload: file,
    });
  };

  let toggleDevices = () => {
    pane = pane === "devices" ? null : "devices";
  };

  let toggle2FA = (value) => {
    if (value === true) {
      pane = "second-factor";
    } else {
      pane = pane === "second-factor" ? null : "second-factor";
    }
  };

  let updateName = _.debounce((e) => {
    nameUpdated = true;

    authorize({
      event: "profile:update",
      updates: { name: e.target.value },
    }).then(() => {
      if (nameTimeout) {
        clearTimeout(nameTimeout);
      }

      nameTimeout = setTimeout(() => {
        nameUpdated = false;
      }, 5000);
    });
  }, 750);
</script>

<div class="rows-1.5">
  <div class="p-3 bg-base-100 rounded-lg flex items-center gap-3 shadow-sm">
    <div
      class="tooltip tooltip-right"
      data-tip={extras?.secondFactorRequired
        ? null
        : !avatarUploaded
          ? "Upload an avatar..."
          : "Change your avatar..."}
    >
      <EditableImage
        disabled={extras?.secondFactorRequired}
        uploaded={uploadAvatar}
        params={{ actor_id: actor?.id }}
        src={actor?.avatar}
        name={actor?.identiconId}
        class="w-12 h-12 rounded-lg"
      />
    </div>

    <div class="grow">
      <div class="text-xl -mt-1 font-bold text-black dark:text-white">
        {actor.identifier}
      </div>
      <div class="text-xs flex items-baseline gap-1">
        <CornerLeftUp size="10" />
        your
        {actor.identifierType}
      </div>
    </div>

    <div
      class="tooltip md:tooltip-open tooltip-left"
      data-tip="Your unique identicon"
    >
      <div class="bg-black dark:bg-black rounded w-10 h-10 min-w-10 ml-0.5">
        <Identicon id={actor.identiconId} class="w-auto z-10" />
      </div>
    </div>
  </div>

  <Alert
    type={(extras?.secondFactorRequired && actor.validSecondFactors) ||
    extras?.secondFactorEnabled
      ? "success"
      : pane == "second-factor"
        ? "secondary"
        : extras?.secondFactorRequired
          ? "warn"
          : "info"}
    class="!p-2 !pl-2 !pr-1 mb-1.5"
  >
    <div class="cols-3">
      {#if extras?.secondFactorEnabled}
        <LockKeyhole size="30" class="ml-2" />

        <div class="pl-1.5">
          <p>
            <span><b>Two-factor auth</b> is now enabled.</span>
          </p>

          <div class="cols-1.5 pt-1">
            {#if auth.client.allowProfiles}
              <PromptContinue
                {auth}
                {loading}
                {authorize}
                event="profile:visit"
                class="!btn-link !btn-xs !min-w-0 !p-0 !text-inherit !h-auto !min-h-0"
                label="Review your profile..."
              />

              <span class="text-sm">or</span>

              <PromptContinue
                {auth}
                {loading}
                {authorize}
                event="profile:verify"
                class="!btn-link !btn-xs !min-w-0 !p-0 !text-inherit !h-auto !min-h-0"
                label="continue..."
              />
            {/if}
          </div>
        </div>
      {:else if extras?.secondFactorRequired}
        {#if actor.validSecondFactors}
          <LockKeyhole size="30" class="ml-2" />
        {:else}
          <LockKeyholeOpen size="30" class="ml-2" />
        {/if}

        <p class="grow pl-2">
          {#if actor.validSecondFactors}
            Enable <b>two-factor auth</b> to continue...
          {:else}
            Set up one or more <b>secondary credentials</b> to continue...
          {/if}
        </p>

        {#if actor.validSecondFactors}
          <PromptContinue
            {auth}
            {loading}
            {authorize}
            event="second-factor:enable"
            class="btn-success !btn-md !text-base !min-w-[90px]"
            label="Enable"
          />
        {/if}
      {:else}
        <p class="grow text-sm cols-1.5">
          {#if pane}
            <button class="btn btn-ghost btn-xs" onclick={() => (pane = null)}>
              <ChevronLeft size="14" class="-mx-1" />
              <span
                >Back <span class="hidden md:inline">to your profile</span
                ></span
              ></button
            >
          {:else}
            {#key actor.lastLoginAt}
              {#if actor.lastLoginAt}
                <LogIn size="14" />

                Last login <Time timestamp={actor.lastLoginAt} />{:else}👋 <b
                  >Welcome!</b
                >
              {/if}
            {/key}
          {/if}
        </p>

        {#if !pane}
          <button class="btn btn-xs btn-info" onclick={toggleDevices}>
            devices
          </button>

          <button
            class="btn btn-xs btn-warning"
            onclick={() => startOver(true)}
          >
            <LogOut size="10" /> logout
          </button>
        {/if}
      {/if}
    </div>
  </Alert>

  {#if pane == "second-factor"}
    <SecondFactor required={extras?.secondFactorRequired} {...props} />
  {:else if pane == "devices"}
    <Devices {prompt} />
  {:else}
    <div class="uppercase font-bold text-xs grow whitespace-nowrap mt-3">
      name & email
    </div>

    {#if actor.identifierType == "email" && nicknameEnabled}
      <label class="input input-bordered flex items-center gap-3">
        <div class="text-xs">nickname</div>

        <input
          class=""
          placeholder="..."
          disabled={actor?.nickname}
          bind:value={actor.nickname}
        />
      </label>
    {/if}

    <label class="input input-bordered cols-3">
      <span class="label-xs">name</span>
      <input
        class="w-full"
        placeholder="Add your name..."
        bind:value={actor.name}
        oninput={updateName}
      />

      {#if loading}
        <span class="loading loading-spinner loading-sm"></span>
      {:else if nameUpdated}
        <UserRoundCheck class={"text-success"} />
      {:else}
        <UserRoundPen />
      {/if}
    </label>

    <div
      class="flex flex-col gap-1.5 mb-3 relative overflow-hidden -m-1.5 rounded"
    >
      <div
        class="flex flex-col gap-1.5 max-h-[250px] overflow-y-auto p-1.5 pb-1.5"
      >
        {#each actor?.loginEmails || [] as email (email.address)}
          {#key email.address}
            <OnboardEmail
              {prompt}
              {authorize}
              {email}
              verifyClass={`btn-xs btn-outline ${email.verifiedAt ? "btn-success" : ""}`}
            />
          {/key}
        {/each}

        {#key actor?.loginEmails?.length}
          <OnboardEmail {prompt} {authorize} />
        {/key}
      </div>

      <div
        class="absolute left-0 right-0 bottom-0 h-[10px] bg-info blur-2xl opacity-50"
      ></div>
    </div>

    <div class="rows-1.5">
      {#if auth?.client?.allowPasswords || auth.client?.allowSecondFactor}
        <div class="cols-3 mb-1.5">
          <div class="uppercase font-bold text-xs">credentials</div>
        </div>

        {#if auth?.client?.allowPasswords}
          <ChangePassword {...props} />
        {/if}

        {#if auth.client.allowSecondFactor}
          <div
            class={`rounded-lg shadow w-full cols-3 p-3 bg-base-100 bg-opacity-50 ${actor.secondFactor ? "" : "border-dashed"}`}
          >
            {#if !actor.secondFactor}
              <div class="ml-1.5 text-warning">
                <LockKeyholeOpen size="18" />
              </div>

              <p class="grow dim ml-1.5 text-sm">
                Two-factor auth is <b>disabled</b>...
              </p>

              <button
                class="btn btn-xs btn-outline"
                onclick={() => toggle2FA(true)}
              >
                enable
              </button>
            {:else}
              <div class="ml-1.5">
                <LockKeyhole class="text-secondary" size="18" />
              </div>

              <p class="grow text-sm">
                Two-factor auth is <b>enabled</b>...
              </p>

              <button
                class="btn btn-xs btn-ghost"
                onclick={() => toggle2FA(true)}
              >
                edit
              </button>
            {/if}
          </div>
        {/if}
      {/if}
    </div>

    {#if singleSignOns?.length}
      <div class="uppercase font-bold text-xs mt-3">social & sso</div>
      <div class="rows-1.5">
        {#each singleSignOns as sso}
          <SingleSignOn {prompt} {authorize} {sso} actor={auth.actor} />
        {/each}
      </div>
    {/if}
  {/if}
</div>
