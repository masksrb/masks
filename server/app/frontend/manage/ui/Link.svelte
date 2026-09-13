<script>
  import { useRouter } from "../lib/router.svelte.js";

  let { to, class: klass = "link link-hover", children, ...rest } = $props();

  const router = useRouter();

  function follow(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if (event.button !== 0) return;

    event.preventDefault();
    event.stopPropagation();

    router.go(to);
  }
</script>

<a {...rest} class={klass} href={router.href(to)} onclick={follow}>{@render children()}</a>
