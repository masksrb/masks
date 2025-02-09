<script>
  import _ from "lodash-es";
  import Adapter from "./adapters/Wrapper.svelte";
  import Alert from "@/components/Alert.svelte";

  let { adapters, change, settings } = $props();
</script>

<div class="rows-3">
  <Alert type="emerald">
    <label class="cols-3">
      <span class="font-bold label-sm"> Location </span>
      <select
        class="select select-sm !outline-none grow"
        onchange={(e) => change({ storageAdapter: e.target.value })}
      >
        <option value="" class="opacity-75">Disabled</option>

        {#each adapters as adapter}
          {#if adapter.storageAdapter}
            <option
              value={adapter.key}
              selected={adapter.key == settings.storageAdapter}
              >{adapter.name}</option
            >
          {/if}
        {/each}
      </select>
    </label>

    <div class="label-xs mt-1.5">
      Used for avatars, logos, and other small assets...
    </div>
  </Alert>

  <div class="divider label-xs my-0">Available locations</div>

  {#each adapters as adapter}
    {#if adapter.storageAdapter}
      <Adapter {adapter} {settings} {change} />
    {/if}
  {/each}

  <Adapter
    {settings}
    {change}
    filter="storageAdapter"
    placeholder="Add more storage..."
    adding
  />
</div>
