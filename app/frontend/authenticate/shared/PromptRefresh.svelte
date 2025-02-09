<script>
  import _ from "lodash-es";
  import { RotateCw, X } from "lucide-svelte";

  import Dialog from "@/components/Dialog.svelte";

  let { authorize, ...props } = $props();
  let open = $state();
</script>

{#if open}
  <Dialog>
    <div class="rows-3 gap-3">
      <div class="cols-3 items-center">
        <div class="mr-1.5">
          <RotateCw class="dim" />
        </div>
        <h3 class="text-3xl md:text-4xl font-bold grow">Session expired...</h3>
      </div>
      <p class="text-2xl mb-6">
        <span class="dim">Your session has timed out.</span>
        <a href={window.location.href} class="underline">Refresh the page</a>
        <span class="dim">to continue...</span>
      </p>

      <div class="h-full grow"></div>
      <div class="grow">
        <a
          href={window.location.href}
          class="btn btn-outline btn-warning btn-lg">Refresh</a
        >
      </div>
    </div>
  </Dialog>
{/if}
