<script>
  import { Info } from "lucide-svelte";
  import Alert from "@/components/Alert.svelte";
  import { gql } from "@urql/svelte";

  let { settings, change, loading, errors, ...props } = $props();
</script>

<div class="flex flex-col gap-1.5">
  <Alert type="info" icon={Info} class="mb-1.5">
    Changes made below only apply to new clients...
  </Alert>

  <div class="bg-base-200 rounded-lg px-4 pt-2 pb-1.5 flex flex-col gap-0 mb-3">
    <label class="label cursor-pointer">
      <span class="label-text-alt"> Allow password login </span>
      <input
        type="checkbox"
        class="toggle toggle-xs"
        checked={settings.clients.allowPasswords}
        onclick={(e) =>
          change({ clients: { allowPasswords: e.target.checked } })}
      />
    </label>
    <label class="label cursor-pointer">
      <span class="label-text-alt"> Allow login links </span>
      <input
        type="checkbox"
        class="toggle toggle-xs"
        checked={settings.clients.allowLoginLinks}
        onclick={(e) =>
          change({ clients: { allowLoginLinks: e.target.checked } })}
      />
    </label>
  </div>
</div>
