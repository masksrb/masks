<script>
  import { createFeedback } from "./lib/feedback.svelte.js";
  import { day } from "./lib/format.js";
  import Card from "./ui/Card.svelte";
  import Notices from "./ui/Notices.svelte";

  let { api, rows, onreleased } = $props();

  const RELEASE = `
    mutation Release($name: String!) {
      releaseNamespace(name: $name) { released }
    }
  `;

  const feedback = createFeedback();

  async function release(row) {
    if (
      !confirm(
        `Release ${row.name}? The next application to ask for it gets it, and the scopes beneath ` +
          `it stop meaning what they mean now.`,
      )
    )
      return;

    const done = await feedback.attempt(
      () => api.query(RELEASE, { name: row.name }),
      `${row.name} is free to be claimed again.`,
    );

    if (done) await onreleased();
  }
</script>

<Card
  title="Namespaces"
  lede="Scope prefixes this application claimed, so it can publish scopes of its own beneath them. One name, one resource, until it is released."
>
  <Notices feedback={feedback.state} />

  <div class="overflow-x-auto">
    <table class="table table-sm">
      <thead>
        <tr>
          <th>Name</th>
          <th class="hidden sm:table-cell">Resource</th>
          <th class="hidden sm:table-cell">Claimed</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        {#each rows as row (row.name)}
          <tr>
            <td class="font-mono text-xs">{row.name}</td>

            <td class="hidden max-w-[18rem] font-mono text-xs opacity-70 sm:table-cell">
              <div class="truncate" title={row.resource}>{row.resource}</div>
            </td>

            <td class="hidden text-xs opacity-70 sm:table-cell">{day(row.claimedAt)}</td>

            <td class="text-right whitespace-nowrap">
              {#if row.releasable}
                <button
                  type="button"
                  class="btn btn-xs btn-error btn-outline"
                  onclick={() => release(row)}
                >
                  Release
                </button>
              {:else}
                <span class="text-xs opacity-60">archive to release</span>
              {/if}
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
</Card>
