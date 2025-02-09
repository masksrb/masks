<script>
  import Alert from "@/components/Alert.svelte";
  import Avatar from "@/components/Avatar.svelte";
  import { Handshake as Icon } from "lucide-svelte";
  import PromptHeader from "../shared/PromptHeader.svelte";
  import PromptContinue from "../shared/PromptContinue.svelte";
  import { Info } from "lucide-svelte";

  let { auth, authorize, loading = $bindable() } = $props();
</script>

<PromptHeader {auth} heading="Grant access?" suffix="?" class="mb-6">
  {#snippet subheading()}
    {auth?.client?.name} will be able to:
  {/snippet}
</PromptHeader>

<div
  class="join join-vertical w-full mb-6 flex flex-col gap-0.5 bg-warn text-neutral-content"
>
  {#if !auth?.scopes?.length}
    <Alert type="info" icon={Icon}>
      <b>{auth?.client?.name}</b> will be granted temporary access to verify
      your account. Personal details <i>will not be shared</i>.
    </Alert>
  {:else}
    <Alert type="info" class="!p-0 mb-3">
      <div class="max-h-[333px] overflow-auto py-1.5 px-1.5 -m-[1px]">
        {#each auth?.scopes || [] as scope}
          {#if !scope.hidden}
            <div
              class="px-3 mr-[2px] text-sm flex items-center gap-3 my-3 overflow-hidden max-w-full"
            >
              <input
                type="checkbox"
                class="checkbox checkbox-xs checkbox-warning"
                checked
                disabled
              />

              <div class="truncate">
                {scope?.detail}
              </div>
            </div>
          {/if}
        {/each}
      </div>
    </Alert>
  {/if}
</div>

<div class="flex gap-3 justify-center">
  <div
    class="w-[64px] h-[64px] bg-base-100 p-1 rounded-lg border border-base-100 shadow"
  >
    <Avatar actor={auth.actor} />
  </div>

  <PromptContinue
    class="btn-success grow"
    label="approve"
    event="authorize"
    {authorize}
    {loading}
  />

  <PromptContinue
    class="btn-error grow"
    event="deny"
    label="deny"
    {loading}
    {authorize}
  />
</div>
