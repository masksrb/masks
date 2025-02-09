<script>
  import PromptLoading from "../shared/PromptLoading.svelte";
  import { onMount } from "svelte";
  import { redirectTimeout } from "@/util";

  let { auth, loading = $bindable() } = $props();

  onMount(() => {
    redirectTimeout(() => {
      window.location.assign(auth.redirectUri);
    }, 500);
  });
</script>

<PromptLoading />
