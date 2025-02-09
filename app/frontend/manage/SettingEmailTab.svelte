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

  let { change, settings, adapters } = $props();
</script>

<div class="rows-3">
  <Alert type="secondary">
    <label class="cols-3">
      <span class="font-bold label-sm">Email provider</span>
      <select
        class="select select-sm !outline-none grow"
        onchange={(e) => change({ emailAdapter: e.target.value })}
      >
        <option value="" class="opacity-75">Disabled</option>

        {#each adapters as adapter}
          {#if adapter.emailAdapter}
            <option
              value={adapter.key}
              selected={adapter.key == settings.emailAdapter}
              >{adapter.name}</option
            >
          {/if}
        {/each}
      </select>
    </label>

    <div class="label-xs mt-1.5">
      Used for notifications and verification emails...
    </div>
  </Alert>

  <div class="rows-1.5">
    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-xs">from</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. mail@example.com..."
        value={settings.emailFrom}
        oninput={(e) => change({ emails: { from: e.target.value } })}
      />
    </label>

    <label class="input input-sm input-bordered flex items-center gap-3">
      <span class="label-xs">reply-to</span>
      <input
        type="text"
        class="grow ml-3"
        placeholder="e.g. no-reply@example.com..."
        value={settings.emailReplyTo}
        oninput={(e) => change({ emails: { replyTo: e.target.value } })}
      />
    </label>
  </div>

  <div class="divider label-xs my-0">Available providers</div>

  <div class="rows-1.5">
    {#each adapters as adapter}
      {#if adapter.emailAdapter}
        <Adapter {adapter} {settings} {change} />
      {/if}
    {/each}
  </div>

  <Adapter
    {settings}
    {change}
    filter="emailAdapter"
    placeholder="Add an email provider..."
  />
</div>
