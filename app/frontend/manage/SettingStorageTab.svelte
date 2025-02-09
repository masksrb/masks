<script>
  import {
    Info,
    Phone,
    MessageSquare,
    Mail,
    Upload,
    ImageUp,
    UserX,
    Trash,
    CalendarX2,
  } from "lucide-svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import Alert from "@/components/Alert.svelte";
  import DiskStorage from "./storage/DiskStorage.svelte";
  import S3Storage from "./storage/S3Storage.svelte";

  let { settings, change, loading, errors, save, ...props } = $props();
  let deleteInactive = $state(settings.actors.lifetime);
  let services = {
    disk: { name: "Filesystem", component: DiskStorage },
    s3: { name: "AWS / S3", component: S3Storage },
  };
</script>

<div class="flex flex-col gap-1">
  <div class="flex items-center gap-2">
    <p class="label-text-alt text-neutral-content opacity-75 truncate grow">
      Store avatars, logos, and other uploads in...
    </p>
    <select
      class="select select-sm dark:select-ghost"
      onchange={(e) => change({ integration: { storage: e.target.value } })}
    >
      {#each Object.entries(services) as [key, service]}
        <option selected={settings.integration.storage == key} value={key}
          >{service.name}</option
        >
      {/each}
    </select>
  </div>

  {#if services[settings.integration.storage]?.component}
    {@const StorageService = services[settings.integration.storage].component}
    <StorageService {change} {settings} />
  {/if}
</div>

<div class="divider my-3 text-xs opacity-75">auto-deletion</div>

<div
  class="px-3 py-2 bg-base-100 rounded-lg flex items-center gap-3 opacity-75 mb-3"
>
  <Info size="14" />

  <div class="text-sm">
    Sessions, devices, tokens, and other ephemeral data get cleaned up
    regularly.
  </div>
</div>

<div class="px-3 py-1.5 bg-base-100 rounded-lg mb-3">
  <div class="flex items-center gap-0">
    <div
      class="bg-error rounded p-[3px] pl-[4px] text-error-content flex items-center justify-center m-1.5"
    >
      <UserX size="14" class="" />
    </div>

    <input
      type="checkbox"
      class="checkbox checkbox-sm ml-3"
      bind:checked={deleteInactive}
    />

    <span class="opacity-75 whitespace-nowrap text-sm pl-3"
      >{deleteInactive
        ? "Delete inactive actors after"
        : "Never delete inactive actors"}</span
    >

    {#if deleteInactive}
      <label
        class="input dark:input-ghost input-sm min-w-0 flex items-center
        gap-0.5 grow ml-1 !pl-1.5 !outline-none"
      >
        <input
          type="text"
          class="!min-w-0 px-0 max-w-[90px] placeholder:opacity-50"
          value={settings.actors.lifetime}
          placeholder="e.g. 1 year"
          oninput={(e) => change({ actors: { lifetime: e.target.value } })}
        />

        <span class="opacity-75 w-full grow whitespace-nowrap"
          >of inactivity...</span
        >
      </label>
    {/if}
  </div>
</div>
