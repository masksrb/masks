<script>
  import {
    Phone,
    Smartphone,
    MessageSquare,
    SquareActivity,
    Mail,
    Upload,
    ImageUp,
  } from "lucide-svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import Alert from "@/components/Alert.svelte";
  import StorageIntegration from "./integrations/Storage.svelte";
  import SMSIntegration from "./integrations/SMS.svelte";
  import EmailIntegration from "./integrations/Email.svelte";
  import MonitoringIntegration from "./integrations/Monitoring.svelte";
  let { change, settings } = $props();

  let integrations = {
    storage: {
      name: "Storage",
      icon: ImageUp,
      component: StorageIntegration,
    },
    sms: {
      name: "Phones",
      icon: Smartphone,
      component: SMSIntegration,
    },
    email: {
      name: "Emails",
      icon: Mail,
      component: EmailIntegration,
    },
    monitoring: {
      name: "Monitoring",
      icon: SquareActivity,
      component: MonitoringIntegration,
    },
  };

  let tab = $state(Object.keys(integrations)[0]);

  let changeTab = (key) => {
    return (e) => {
      e.preventDefault();
      e.stopPropagation();

      tab = key;
    };
  };
</script>

<div class="flex items-center flex-wrap gap-3">
  {#each Object.entries(integrations) as [key, entry]}
    <button
      class={`btn btn-xs ${tab == key ? "btn-info" : "btn-neutral"}`}
      onclick={changeTab(key)}
    >
      <entry.icon size="14" />
      {entry.name}
    </button>
  {/each}
</div>

{#if integrations[tab]}
  {@const Integration = integrations[tab].component}
  <Integration {settings} {change} />
{/if}
