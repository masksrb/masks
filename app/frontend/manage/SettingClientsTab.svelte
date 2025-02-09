<script>
  import { Info } from "lucide-svelte";
  import Alert from "@/components/Alert.svelte";
  import ClientSettings from "./ClientSettings.svelte";

  let { settings, change } = $props();
</script>

<Alert type="info" icon={Info} class="mb-3">
  Changes made below only apply to new clients...
</Alert>

<ClientSettings
  client={settings.defaultClient}
  change={(v) => change({ clientDefaults: v })}
  defaults
/>
