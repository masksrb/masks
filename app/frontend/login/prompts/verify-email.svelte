<script>
  import Alert from "@/components/Alert.svelte";
  import PromptHeader from "../shared/PromptHeader.svelte";
  import PromptIdentifier from "../shared/PromptIdentifier.svelte";
  import OnboardEmail from "../shared/OnboardEmail.svelte";
  import { MailCheck as Mail, User } from "lucide-svelte";

  let { auth, authorize, loading = $bindable() } = $props();

  let extras = [];
  let primary;
</script>

<PromptHeader
  heading={auth?.actor?.loginEmails?.length
    ? "Verify your email..."
    : "Add an email..."}
  client={auth.client}
  redirectUri={auth.redirectUri}
  class="mb-6"
/>

<PromptIdentifier {auth} class="mb-3" />

<Alert type="warn" icon={Mail} class="mb-3">
  <p>A recently verified e-mail address is <b>required</b> to continue.</p>
</Alert>

<div>
  {#if auth?.actor && !auth?.actor?.loginEmails?.length}
    <OnboardEmail
      {authorize}
      prefix="verified-email"
      {auth}
      class="flex-col w-full !items-start"
      inputClass="grow w-full input-lg mb-1.5"
      btnClass="btn-lg btn-success"
    />
  {:else}
    {#each auth?.actor?.loginEmails || [] as email}
      <OnboardEmail
        {authorize}
        prefix="verified-email"
        {auth}
        {email}
        verifyClass="btn-success btn-sm my-1"
      />
    {/each}
  {/if}
</div>
