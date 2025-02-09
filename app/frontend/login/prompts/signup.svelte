<script>
  import _ from "lodash-es";
  import Alert from "@/components/Alert.svelte";
  import Dialog from "@/components/Dialog.svelte";
  import PromptHeader from "../shared/PromptHeader.svelte";
  import PromptIdentifier from "../shared/PromptIdentifier.svelte";
  import PromptContinue from "../shared/PromptContinue.svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import ProviderIcon from "@/components/ProviderIcon.svelte";
  import PromptFocused from "../shared/PromptFocused.svelte";
  import {
    Mail,
    Unlink,
    X,
    ArrowRight,
    AlertTriangle,
    Lock,
    User,
    UserPlus,
  } from "lucide-svelte";

  let { auth, authorize, startOver, prompt, loading } = $props();

  let denied = $state();
  let sso = $derived(prompt?.extras?.sso);
  let signup = $state(prompt.extras.signup?.actor || {});
  let signupError = $state();
  let signupConfirmed = $state();

  let onsubmit = async (e) => {
    e.preventDefault();
    e.stopPropagation();

    const result = await authorize({
      event: "signup:create",
      updates: { signup },
    });

    signupError = result.extras?.signup?.error;
    signupConfirmed = result.extras?.signup?.confirmed;
  };

  let updateSignup = _.debounce(() => {
    signupError = null;
  }, 500);

  let validSignup = () => {
    if (auth.client.allowPasswords && !signup.password) {
      return false;
    }

    if (!signup.nickname && !signup.email) {
      return false;
    }

    if (signup.email && !signup.email.match(/.+@.+\..+/)) {
      return false;
    }

    if (
      signup.nickname &&
      (signup.nickname.length < auth.settings.nicknameMinChars ||
        signup.nickname.length > auth.settings.nicknameMaxChars)
    ) {
      return false;
    }

    if (signup.password && !signup.validPassword) {
      return false;
    }

    if (auth.client.termsUrl && !signup.terms) {
      return false;
    }

    return signup.email || signup.nickname;
  };

  let isChanged = () => {
    return !_.isEqual({ terms: false, validPassword: undefined }, signup);
  };
</script>

{#if signupConfirmed}
  <PromptHeader class="mb-6">
    {#snippet heading()}
      <div class="">Welcome!</div>
    {/snippet}
  </PromptHeader>

  <PromptIdentifier {auth} class="mb-3" />

  <Alert type="success" class="mb-6">
    👋 <b>Your account has been created.</b> You can log in using the credentials
    you just entered.
  </Alert>

  <div class="cols gap-6 text-lg">
    <PromptContinue class="btn-success" event={"signup:confirm"} {authorize} />

    <span class="label-lg"
      >to <span class="font-bold">{auth.client.name}</span>...</span
    >
  </div>
{:else}
  <PromptHeader client={auth.client} class="mb-6">
    {#snippet heading()}
      <div class="">Sign up...</div>
    {/snippet}
  </PromptHeader>

  {#if sso}
    <Alert type="info" class="mb-6">
      <div class="flex items-start gap-1.5">
        <p>
          Your <b>{sso.provider.name}</b> account will be linked once you sign up...
        </p>

        <div>
          <PromptContinue
            confirm={`Are you sure you want to cancel linking your ${sso.provider.name} account?`}
            label={null}
            icon={X}
            class="!btn-xs btn-error btn-outline !min-w-0 whitespace-nowrap"
            type="submit"
            event={"sso:reset"}
            {authorize}
          >
            {#snippet children()}
              Cancel
            {/snippet}
          </PromptContinue>
        </div>
      </div>
    </Alert>
  {/if}

  <form action="#" {onsubmit}>
    {#if auth.client?.allowNicknames}
      <label
        class={[
          "input input-lg input-bordered flex items-center gap-4 w-full mb-3",
          denied ? "input-warning" : "",
        ].join(" ")}
      >
        <User />

        <input
          minlength={auth.settings.nicknameMinChars}
          maxlength={auth.settings.nicknameMaxChars}
          class="w-full placeholder:text-sm md:placeholder:text-base"
          placeholder={`Enter a nickname...`}
          type="text"
          bind:value={signup.nickname}
          oninput={updateSignup}
        />
      </label>
    {/if}

    {#if auth.client?.allowEmails}
      <label
        class={[
          "input input-lg input-bordered flex items-center gap-4 w-full mb-3",
          denied ? "input-warning" : "",
        ].join(" ")}
      >
        <Mail />

        <input
          class="w-full placeholder:text-sm md:placeholder:text-base"
          placeholder={`Enter an email address...`}
          type="text"
          bind:value={signup.email}
          oninput={updateSignup}
        />
      </label>
    {/if}

    {#if auth.client?.allowPasswords}
      <PasswordInput
        {auth}
        class="input-lg mb-3 gap-4 w-full"
        bind:value={signup.password}
        bind:valid={signup.validPassword}
        placeholder="Enter a password"
        onChange={updateSignup}
      >
        {#snippet before()}<Lock />{/snippet}
      </PasswordInput>
    {/if}

    {#if auth.client.termsUrl}
      <div class="box bg-base-300 mb-3">
        <label class="label cursor-pointer gap-3">
          <input
            type="checkbox"
            class="toggle toggle-sm toggle-success"
            bind:checked={signup.terms}
          />

          <span class="grow ml-1.5">
            Accept the <a
              class="underline"
              target="_blank"
              href={auth.client.termsUrl}>terms and conditions</a
            >...</span
          >
        </label>
      </div>
    {/if}

    {#if signupError}
      <Alert type="warn" class="mb-3" icon={AlertTriangle}>
        {signupError}
      </Alert>
    {/if}

    <PromptContinue
      label="Sign up"
      type="submit"
      event="signup:create"
      updates={{ signup }}
      disabled={!validSignup()}
      denied={signupError}
      {loading}
      class={`w-full btn-outline !min-w-0 ${signupError ? "btn-warning" : "btn-success"}`}
    />

    <PromptContinue
      class={"mt-3 w-full btn-link text-base-content no-underline md:text-lg text-sm"}
      onclick={startOver}
    >
      <span class="cols-3">
        <span class="md:label-lg grow font-normal whitespace-nowrap">
          Already signed up?
        </span>

        <span class="underline whitespace-nowrap">Log in...</span>
      </span>
    </PromptContinue>
    <!--
  <PromptContinue
    type="submit"
    {denied}
    {loading}
    disabled={!value}
    class={`-mr-6 !min-w-0 ${denied ? "btn-warning" : "btn-info"}`}
  /> -->
  </form>
{/if}
