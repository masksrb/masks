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
<PasswordInput
  label="Key ID"
  class="whitespace-nowrap"
  placeholder="..."
  value={provider.settings?.keyId}
  onChange={(e) => change({ settings: { keyId: e.target.value } })}
/>

<PasswordInput
  label="Team ID"
  class="whitespace-nowrap"
  placeholder="..."
  value={provider.settings?.teamId}
  onChange={(e) => change({ settings: { teamId: e.target.value } })}
/>
<PasswordInput
  label="PEM"
  class="whitespace-nowrap"
  placeholder="..."
  value={provider.settings?.pem}
  onChange={(e) => change({ settings: { pem: e.target.value } })}
/>
