<script>
  import { CircleHelp as Icon } from "lucide-svelte";
  import Alert from "@/components/Alert.svelte";
  import PromptHeader from "../shared/PromptHeader.svelte";
  import PromptBack from "../shared/PromptBack.svelte";

  let { auth } = $props();
</script>

<PromptHeader
  heading="Invalid request..."
  client={auth.client}
  redirectUri={auth.redirectUri}
  class="mb-6"
/>

<Alert type="error" icon={Icon} class="mb-6">
  The supplied <code>redirect_uri</code> cannot be used.
</Alert>

<PromptBack />
