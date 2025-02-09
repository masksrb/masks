<script>
  import { Info, X, Send, Mail } from "lucide-svelte";
  import Alert from "@/components/Alert.svelte";
  import SSOHeader from "../shared/SSOHeader.svelte";
  import { redirectTimeout } from "@/util.js";
  import PromptFocused from "../shared/PromptFocused.svelte";

  let { auth } = $props();
  let { provider, redirect } = auth.extras;

  if (redirect) {
    redirectTimeout(() => {
      window.location.assign(redirect);
    }, 1000);
  }
</script>

<PromptFocused>
  <SSOHeader {auth} {provider}>
    {#snippet heading()}
      Sending you to <a href={provider?.redirect} class="font-bold"
        >{provider?.name}</a
      >...
    {/snippet}
    {#snippet alert()}
      <Alert type="neutral" icon={Info} class="mb-5">
        <p class="text-lg m-1">
          You will be sent back here after you log in with your <b
            >{provider?.name}</b
          > credentials.
        </p>
      </Alert>
    {/snippet}
  </SSOHeader>

  <div class="text-center pt-6">
    <span class="loading loading-dots loading-lg mx-auto opacity-50"></span>
  </div>
</PromptFocused>
