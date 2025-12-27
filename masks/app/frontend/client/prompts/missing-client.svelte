<script>
import { AlertTriangle, CircleHelp as Icon } from "lucide-svelte";
import PromptFocused from "../shared/PromptFocused.svelte";
import PromptExit from "../shared/PromptExit.svelte";

let { auth, settings } = $props();
</script>

<PromptFocused
  icon={AlertTriangle}
  iconClass="text-error mx-auto block"
  title="Login failed..."
>
  <p class="text-center dim text-xl mb-6">Your request to log in is invalid.</p>

  <PromptExit {settings} />
</PromptFocused>
