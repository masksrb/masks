<script>
  let { columns, count, empty, rows } = $props();

  const heads = $derived(
    columns.map((column) => (typeof column === "string" ? { label: column } : column)),
  );
</script>

{#if count === 0}
  <div class="rounded-box border border-base-300 bg-base-100 px-6 py-14 text-center">
    <p class="mx-auto max-w-sm text-sm opacity-70">{empty}</p>
  </div>
{:else}
  <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
    <table class="table">
      <thead>
        <tr>
          {#each heads as head, index (index)}
            <th
              class="{head.right ? 'text-right' : ''} {head.hide ? 'hidden md:table-cell' : ''}"
            >{head.label ?? ""}</th>
          {/each}
        </tr>
      </thead>
      <tbody>{@render rows()}</tbody>
    </table>
  </div>
{/if}
