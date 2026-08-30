<script>
let { login } = $props();
</script>

<div
  class="flex items-baseline justify-between gap-3 rounded-lg border border-base-content/15 bg-base-200 px-3 py-2"
>
  <span class="text-sm opacity-75 break-all">{login.auth.identifier}</span>
  <button
    type="button"
    class="btn btn-link btn-xs h-auto min-h-0 flex-none p-0"
    disabled={login.loading}
    onclick={() => login.startOver()}>Not you?</button
  >
</div>
