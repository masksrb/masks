<script>
  import { useRouter } from "../lib/router.svelte.js";

  let { to, children } = $props();

  const router = useRouter();

  function follow(event) {
    if (event.target.closest("a, button, input, label")) return;
    if (getSelection()?.toString()) return;

    router.go(to);
  }
</script>

<tr class="hover cursor-pointer" onclick={follow}>{@render children()}</tr>
