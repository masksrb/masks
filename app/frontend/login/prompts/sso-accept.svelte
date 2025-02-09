<script>
  import { Link } from "lucide-svelte";
  import Alert from "@/components/Alert.svelte";
  import SSOHeader from "../shared/SSOHeader.svelte";
  import PromptContinue from "../shared/PromptContinue.svelte";
  import PromptFocused from "../shared/PromptFocused.svelte";

  let { auth, authorize } = $props();
  let { provider } = auth.extras;
</script>

<PromptFocused>
  <SSOHeader {auth} {provider}>
    {#snippet heading()}
      {#if auth.trusted}
        Link your <b class="font-bold">{provider?.name}</b> account?
      {:else}
        Your
        <b class="font-bold">{provider?.name}</b> account is not linked...
      {/if}
    {/snippet}

    {#snippet alert()}
      <Alert type="info" icon={Link} class="mb-6">
        <p class="text-lg m-1">
          You can log in using your existing credentials to link accounts, or
          try a different way to log in.
        </p>
      </Alert>
    {/snippet}
  </SSOHeader>

  <div class="flex items-center gap-3 w-full justify-center">
    <PromptContinue
      label={`Log in`}
      type="submit"
      class="btn-info"
      event={"sso:login"}
      {authorize}
    />

    <PromptContinue
      confirm="Are you sure you want to start over?"
      label={`Start over`}
      iconClass="opacity-75"
      type="submit"
      event={"sso:reset"}
      {authorize}
    />
  </div>
</PromptFocused>
