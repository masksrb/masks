<script>
  import { OctagonAlert as Icon } from "lucide-svelte";
  import Alert from "@/components/Alert.svelte";
  import PromptHeader from "../shared/PromptHeader.svelte";
  import PromptIdentifier from "../shared/PromptIdentifier.svelte";

  let { auth, startOver } = $props();
</script>

<PromptHeader
  heading="Access denied..."
  client={auth.client}
  redirectUri={auth.redirectUri}
  class="mb-6"
/>

<Alert type="error" icon={Icon} class="mb-3">
  You do not have permission to continue. Contact an administrator for access.
</Alert>

<PromptIdentifier {auth} class="mb-6" {startOver} />

<div class="flex items-center gap-6">
  <a href={auth.redirectUri} class="btn btn-error btn-lg text-lg"> Go back </a>
</div>
