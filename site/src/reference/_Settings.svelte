<script>
  let props = $props();
  let list = $derived(
    Object.entries(props.settings || {}).map(([name, settings]) => {
      return { name, ...settings };
    })
  );
</script>

{#if list.length}
  <div class="flex flex-col gap-1.5 !mb-10">
    {#each list as setting}
      <div
        class="flex items-center gap-3 px-3 pb-1.5 pt-1 rounded-lg !my-0 dark:bg-gray-950 bg-gray-100"
      >
        <div class="flex flex-col grow">
          <span
            class="font-bold flex items-baseline gap-3 !m-0"
            id={setting.name}
          >
            {setting.name}

            {#if setting.env}
              <span class="font-mono text-xs opacity-75">{setting.env}</span>
            {:else if setting.env_only}
              <span
                class="font-mono text-xs opacity-75 text-indigo-700 dark:text-indigo-400"
                >{setting.env_only}</span
              >
            {/if}

            <span class="font-mono font-normal text-xs opacity-75"
              >{setting.type}</span
            >
          </span>
          <span class="text-sm opacity-75 !m-0">
            {setting.desc}.
            {#if setting.env_only}
              <span class="text-indigo-900 dark:text-indigo-200 text-xs"
                >Accepted via ENV var only.</span
              >
            {/if}
          </span>
        </div>

        <div class="flex flex-col gap-1.5 !mt-0 text-xs text-right">
          {#if !setting.readonly}
            <span class="opacity-50">default</span>
            <span class="font-mono">{setting.default}</span>
          {:else}
            <i class="opacity-50">read-only</i>
          {/if}
        </div>
      </div>
    {/each}
  </div>
{/if}
