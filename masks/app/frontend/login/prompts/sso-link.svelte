<script>
import Icon from "@iconify/svelte";
import { Link, Unlink, X, Send, Mail } from "lucide-svelte";
import Alert from "@/components/Alert.svelte";
import SSOHeader from "../shared/SSOHeader.svelte";
import PromptContinue from "../shared/PromptContinue.svelte";
import { iconifyProvider } from "@/lib";
import PromptFocused from "../shared/PromptFocused.svelte";

let { auth, authorize } = $props();

let { sso } = $derived(auth.extras);
let { provider } = $derived(sso);
let failed = $derived(auth?.warnings?.includes("invalid-sso"));
</script>

<PromptFocused>
  <SSOHeader
    {auth}
    {provider}
    errors={failed
      ? [`Your ${provider.name} account is already in use or invalid.`]
      : null}
  >
    {#snippet heading()}
      {#if failed}
        Unable to link your
        <b class="font-bold">{provider?.name}</b> account
      {:else if sso?.linked}
        <b class="font-bold">{provider?.name}</b> account linked!
      {:else}
        Link your
        <b class="font-bold">{provider?.name}</b> account?
      {/if}
    {/snippet}

    {#snippet alert()}
      {#if failed}
        <Alert
          type="error"
          errors={[
            `Your ${provider.name} account is already in use or invalid.`,
          ]}
        />
      {:else if sso?.linked}
        <Alert type="success">
          {#snippet children()}
            You can now use your {provider.name} account to log in.
          {/snippet}
        </Alert>
      {/if}
    {/snippet}
  </SSOHeader>

  <div class="flex flex-col gap-3 mb-10">
    <div class={`divider -my-3 ${failed ? "text-error" : ""}`}>
      <div>
        {#if failed}<Unlink size="12" />{:else}<Link size="12" />{/if}
      </div>
    </div>

    <Alert type="info">
      <div class="flex items-center gap-3 text-xl font-bold">
        <div
          class="bg-info text-info-content rounded-full overflow-hidden w-10 h-10 flex items-center justify-center"
        >
          {#if sso?.avatar}
            <img alt="Your avatar" src={sso.avatar} />
          {:else}
            <Icon icon={iconifyProvider(provider)} />
          {/if}
        </div>

        <div>
          {sso.identifier}
        </div>
      </div>
    </Alert>
  </div>

  <div class="flex items-center gap-3 w-full justify-center">
    {#if sso?.linked}
      <PromptContinue label={`Continue`} type="submit" {authorize} />
    {:else}
      <PromptContinue
        confirm="Are you sure you want to link accounts?"
        label={`Link`}
        deniedLabel={"Link"}
        type="submit"
        disabled={failed}
        denied={failed}
        class={failed ? "btn-error" : "btn-info"}
        event={"sso:link"}
        {authorize}
      />

      <PromptContinue
        confirm="Are you sure you want to cancel?"
        label={`Skip`}
        iconClass="opacity-75"
        type="submit"
        event={"sso:reset"}
        {authorize}
      />
    {/if}
  </div>
</PromptFocused>
