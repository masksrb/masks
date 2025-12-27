<script>
import PasswordInput from "@/components/PasswordInput.svelte";

let { change, provider, ...props } = $props();
</script>

<label class="input input-bordered flex items-center gap-3">
  <div class="whitespace-nowrap label-xs">Client ID</div>

  <input
    type="text"
    class="grow w-full"
    placeholder="..."
    value={provider.settings?.clientId}
    oninput={(e) => change({ settings: { clientId: e.target.value } })}
  />
</label>

<PasswordInput
  label="Client secret"
  class="whitespace-nowrap"
  placeholder="..."
  value={provider.settings?.clientSecret}
  onChange={(e) => change({ settings: { clientSecret: e.target.value } })}
/>

<label class="input input-bordered flex items-center gap-3">
  <div class="whitespace-nowrap label-xs">Scopes</div>

  <input
    type="text"
    class="grow w-full"
    placeholder="..."
    value={provider.settings?.scopes}
    oninput={(e) => change({ settings: { scopes: e.target.value } })}
  />
</label>
