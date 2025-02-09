<script>
  import _ from "lodash-es";
  import {
    Pen,
    Phone,
    PlusSquare,
    Smartphone,
    MessageSquare,
    SquareActivity,
    Mail,
    Upload,
    ImageUp,
    Trash2,
  } from "lucide-svelte";
  import Adapter from "./adapters/Wrapper.svelte";
  import Alert from "@/components/Alert.svelte";

  let { adapters, change, settings } = $props();
</script>

<div class="rows-3">
  <div class="rows-3">
    <Alert type="primary">
      <label class="cols-3">
        <span class="font-bold label-sm">SMS provider</span>

        <select
          class="select select-sm !outline-none grow"
          onchange={(e) => change({ phoneAdapter: e.target.value })}
        >
          <option value="" class="opacity-75">Disabled</option>

          {#each adapters as adapter}
            {#if adapter.phoneAdapter}
              <option
                value={adapter.key}
                selected={adapter.key == settings.phoneAdapter}
                >{adapter.name}</option
              >
            {/if}
          {/each}
        </select>
      </label>

      <div class="label-xs mt-1.5">
        Used for two-factor auth using SMS and/or voice...
      </div>
    </Alert>

    <div class="rows-1.5">
      <label class="input input-sm input-bordered flex items-center gap-3">
        <span class="label-xs">default country code</span>
        <input
          type="text"
          class="grow ml-3"
          value={settings.phoneCountry}
          oninput={(e) => change({ phoneCountry: e.target.value })}
        />
      </label>
    </div>

    <div class="divider label-xs my-0">Available providers</div>

    {#each adapters as adapter}
      {#if adapter.phoneAdapter}
        <Adapter {adapter} {settings} {change} />
      {/if}
    {/each}

    <Adapter
      {settings}
      {change}
      filter="phoneAdapter"
      placeholder="Add an SMS provider..."
    />
  </div>
</div>
