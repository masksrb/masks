<script>
  import { X } from "lucide-svelte";
  import PromptHeader from "../shared/PromptHeader.svelte";
  import PromptBack from "../shared/PromptBack.svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";

  let { auth } = $props();
</script>

<PromptHeader
  heading="Invalid request"
  client={auth.client}
  redirectUri={auth.redirectUri}
/>

<div class="alert flex items-center gap-3 rounded-lg mb-6 text-left">
  <X class="text-error" />
  <p class="text-xl">
    The supplied <code>response_type</code> is unsupported.
  </p>
</div>

<PromptBack />
