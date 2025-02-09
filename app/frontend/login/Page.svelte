<script>
  import _ from "lodash-es";
  import { ArrowRight, ChevronRight, Info } from "lucide-svelte";
  import VerificationDialog from "./factors/VerificationDialog.svelte";
  import PromptLoadingError from "./shared/PromptLoadingError.svelte";
  import PromptLoading from "./shared/PromptLoading.svelte";
  import PromptRefresh from "./shared/PromptRefresh.svelte";
  import PromptContinue from "./shared/PromptContinue.svelte";
  import { toasts } from "@/lib/toast";
  import { onMount, setContext, getContext } from "svelte";

  const prompts = import.meta.glob("./prompts/*.svelte");

  let { backend, ...props } = $props();
  let { root, masks } = getContext("page");

  let prompt = $state(props.login ? masks.login(props.login) : null);
  let auth = $derived(prompt?.auth);
  let loading = $state();
  let Prompt = $state(PromptLoading);
  let settings = $derived(auth?.settings || backend?.settings);
  let hasLogo = $derived(settings?.lightLogoUrl || settings?.darkLogoUrl);

  let override = async (p) => {
    await refreshPrompt(backend, p);

    return p;
  };

  let startOver = async (opts) => {
    let logout = opts.preventDefault ? null : opts;

    override(await prompt.startOver(logout));
  };
  const authorize = async (input) => {
    return override(await prompt.refresh(input));
  };

  let cancelSudo = () => {
    override(prompt.endSudo());
  };

  let args = $derived({
    prompt,
    auth,
    loading,
    authorize,
    startOver,
    override,
    settings,
    backend,
  });

  onMount(async () => {
    await refreshPrompt(backend, prompt);

    if (auth?.id) {
      authorize({});
    }
  });

  let refreshPrompt = async (backend, nextPrompt) => {
    let backendPrompt = backend?.prompt
      ? `./prompts/${backend?.prompt}.svelte`
      : null;

    let auth = nextPrompt?.auth;

    let frontendPrompt = auth?.prompt
      ? `./prompts/${auth?.prompt}.svelte`
      : null;

    let loader;

    if (backendPrompt && prompts[backendPrompt]) {
      loader = prompts[backendPrompt];
    } else if (prompts[frontendPrompt]) {
      loader = prompts[frontendPrompt];
    } else if (prompt?.loadingError) {
      Prompt = PromptLoadingError;
    } else {
      Prompt = PromptLoading;
    }

    if (!Prompt) {
      Prompt = PromptLoading;
    }

    loading = true;

    if (loader) {
      try {
        let mod = await loader();
        Prompt = mod.default;
      } catch (e) {
        console.log(e);
      }
    }

    prompt = nextPrompt;
    loading = false;
    canContinue = false;
  };

  let innerWidth = $state();
  let autofocus = $derived(innerWidth > 768);
  let canContinue = $state();

  $effect(() => {
    setContext("autofocus", autofocus);
  });
</script>

<svelte:window bind:innerWidth />

<PromptRefresh />

{#if prompt?.verifying}
  <VerificationDialog {...args} onclose={cancelSudo} />
{/if}

<div
  class="background animate-fade-in flex flex-col min-h-full md:p-3 px-[5px] items-center justify-center"
>
  <div
    class="w-full max-w-[500px] md:w-[500px] mx-auto rounded-b-2xl shadow-2xl"
  >
    <div
      class={`bg-white dark:bg-black !bg-opacity-10 h-[25px] md:h-[32px] rounded-t-2xl w-full relative border-t dark:border-gray-700 border-gray-200`}
    ></div>
    <div
      class="md:w-[500px] bg-white dark:bg-black !bg-opacity-90 w-full md:px-8 pb-5 px-5"
    >
      {#snippet logo()}
        <div class="cols-1.5">
          {#if hasLogo}
            <div class="max-w-[300px]">
              {#if settings?.lightLogoUrl}
                <img
                  alt={`${settings?.themeName} logo`}
                  src={settings?.lightLogoUrl}
                  class="object-scale-down h-10 rounded dark:hidden"
                />
              {/if}

              {#if settings?.darkLogoUrl}
                <img
                  alt={`${settings?.themeName} logo`}
                  src={settings?.darkLogoUrl}
                  class="object-scale-down h-10 rounded hidden dark:block"
                />
              {/if}
            </div>
          {:else}
            <p
              class="font-bold grow text-left text-lg md:text-xl group-hover:underline group-focus:underline"
            >
              {settings?.theme?.name}
            </p>
          {/if}

          <div class="grow"></div>

          {#if auth?.client && canContinue}
            <PromptContinue
              {authorize}
              event={canContinue}
              class="btn !btn-md !py-1.5 !px-3 btn-ghost cols-1.5 !text-xs !min-w-0"
            >
              <p class="rows items-end">
                <span class="font-normal cols-1.5"
                  ><span>continue to</span> <ArrowRight size="10" /></span
                ><span>{auth?.client?.name}</span>
              </p>
            </PromptContinue>
          {/if}
        </div>
      {/snippet}

      {#if settings?.theme?.url}
        <a
          href={settings?.theme?.url}
          class="flex items-center gap-4 group !outline-none"
        >
          {@render logo()}
        </a>
      {:else}
        {@render logo()}
      {/if}

      <div class="grow"></div>
    </div>
    <div class="w-full md:w-[500px] mx-auto relative rounded-b-2xl shadow-xl">
      <div
        class="bg-white dark:bg-black !bg-opacity-90 w-full min-h-[200px] md:w-[500px] mx-auto"
      >
        <div class="px-5 md:px-8">
          {#if Prompt}
            <Prompt
              {...args}
              {prompt}
              {authorize}
              {startOver}
              canContinue={(v) => (canContinue = v)}
              loading={loading || prompt.loading}
              auth={prompt.auth}
              {override}
            />
          {/if}
        </div>
      </div>
      <div
        class={`bg-white dark:bg-black !bg-opacity-90 h-[30px] overflow-hidden rounded-b-2xl`}
      ></div>
    </div>
  </div>
</div>

{#if $toasts.length}
  <div
    class={`w-full fixed left-0 right-0 bottom-0 p-6 md:p-12 animate-fade-in`}
  >
    <div class="max-w-[500px] mx-auto">
      <div
        class={[
          "box bg-accent",
          "shadow-2xl cols-3 text-accent-content text-xl rounded-full font-bold",
        ].join(" ")}
      >
        <Info size="25" class="ml-1 dim" />

        {$toasts[0]}
      </div>
    </div>
  </div>
{/if}
