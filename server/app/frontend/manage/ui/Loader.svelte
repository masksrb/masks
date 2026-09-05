<script>
  import Spinner from "./Spinner.svelte";

  let { load, children } = $props();

  let state = $state({ loading: true, failure: null, data: null });

  async function run() {
    state.loading = true;
    state.failure = null;

    try {
      state.data = await load();
    } catch (thrown) {
      state.failure = thrown.message;
    } finally {
      state.loading = false;
    }
  }

  run();
</script>

{#if state.loading}
  <Spinner />
{:else if state.failure}
  <div class="alert alert-error alert-soft text-sm" role="alert">
    <span>{state.failure}</span>
    <button type="button" class="btn btn-sm" onclick={run}>Try again</button>
  </div>
{:else}
  {@render children(state.data, run)}
{/if}
