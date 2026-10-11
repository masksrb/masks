<script>
  let { marks } = $props();

  const SHAPES = {
    manager: '<path d="M10 2.75 16 5v4.6c0 3.7-2.5 6.4-6 7.65-3.5-1.25-6-3.95-6-7.65V5z"/>',
    key: '<circle cx="6.75" cy="10" r="3.25"/><path d="M10 10h7.25M14.5 10v2.5M17.25 10v2"/>',
    invited: '<rect x="2.75" y="4.75" width="14.5" height="10.5" rx="1.5"/><path d="m3.25 5.5 6.75 5.25 6.75-5.25"/>',
    unconfirmed: '<circle cx="10" cy="10" r="7"/><path d="M10 6.25v4.5M10 13.75v.01"/>',
    waiting: '<circle cx="10" cy="10" r="7"/><path d="M10 6.25V10l2.75 1.75"/>',
    help: '<circle cx="10" cy="10" r="7"/><path d="M7.9 7.9a2.15 2.15 0 1 1 3 1.95c-.55.3-.9.75-.9 1.3v.35M10 13.75v.01"/>',
    suspended: '<circle cx="10" cy="10" r="7"/><path d="M8.1 7.25v5.5M11.9 7.25v5.5"/>',
    blocked: '<circle cx="10" cy="10" r="7"/><path d="m5.05 5.05 9.9 9.9"/>',
    dynamic: '<path d="M7 3.25v3.5M13 3.25v3.5"/><rect x="4.75" y="6.75" width="10.5" height="5.5" rx="1.5"/><path d="M10 12.25v4.5"/>',
    archived: '<rect x="2.75" y="4" width="14.5" height="3.5" rx="1"/><path d="M4.25 7.5v7.25c0 .7.55 1.25 1.25 1.25h9c.7 0 1.25-.55 1.25-1.25V7.5M8.25 10.5h3.5"/>',
  };
</script>

{#if marks.length}
  <span class="marks">
    {#each marks as [shape, label, tone] (shape)}
      <span class="mark mark-{tone ?? 'quiet'}" role="img" aria-label={label} title={label}>
        <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          {@html SHAPES[shape]}
        </svg>
      </span>
    {/each}
  </span>
{/if}
