<script>
  import _ from "lodash-es";
  import {
    MailMinus,
    MailCheck,
    MailX,
    Check,
    AlertTriangle,
    RotateCcw,
    MailPlus,
    Trash2 as Trash,
    User,
  } from "lucide-svelte";
  import Page from "./Page.svelte";
  import Alert from "@/components/Alert.svelte";
  import Dropdown from "@/components/Dropdown.svelte";
  import Time from "@/components/Time.svelte";
  import Avatar from "@/components/Avatar.svelte";
  import Identicon from "@/components/Identicon.svelte";
  import EditableImage from "@/components/EditableImage.svelte";
  import {
    mutationStore,
    queryStore,
    gql,
    getContextClient,
  } from "@urql/svelte";

  let props = $props();
  let graphql = getContextClient();
  let actor = $state(props.actor);
  let emails = $state(props.actor?.loginEmails || []);
  let saving = $state(false);
  let loading = $state(true);
  let errors = $state();

  let save = (updates) => {
    updates = updates;
    saving = true;

    let update = mutationStore({
      client: graphql,
      query: gql`
        mutation ($input: EmailInput!) {
          email(input: $input) {
            emails {
              address
              verifiedAt
            }

            errors
          }
        }
      `,
      variables: { input: { ...updates, actorId: actor.id } },
    });

    update.subscribe((r) => {
      errors = r?.data?.email?.errors;
      errors = errors?.length ? errors : null;
      saving = r?.fetching;

      if (!saving && !errors) {
        loading = false;
        emails = r.data.email.emails;
      }
    });
  };

  let saveValues = (values) => {
    return () => {
      save(values);
    };
  };

  let address = $state("");

  let addEmail = () => {
    save({ address, action: "create" });
  };

  let verifyEmail = (address) => {
    return () => {
      save({ address, action: "verify" });
    };
  };

  let unverifyEmail = (address) => {
    return () => {
      save({ address, action: "unverify" });
    };
  };

  let deleteEmail = (address) => {
    return () => {
      if (confirm("Delete this email address?")) {
        save({ address, action: "delete" });
      }
    };
  };
</script>

<div class="flex flex-col gap-3">
  {#if errors?.length}
    <Alert type="error" icon={AlertTriangle}>
      <ul>
        {#each errors as error}
          <li>{error}</li>
        {/each}
      </ul>
    </Alert>
  {/if}

  {#each emails as email}
    <div
      class="flex items-start gap-1.5 text-sm p-1.5 pl-3 bg-base-100 rounded-lg"
    >
      <div class="grow flex flex-col">
        <a href={`mailto:${email.address}`} class="underline font-mono grow">
          {email.address}
        </a>
        {#if email.verifiedAt}
          <span class="pr-1.5 text-xs opacity-75">
            verified <Time timestamp={email.verifiedAt} />
          </span>
        {:else}
          <span class="opacity-75 text-xs opacity-75 pr-1.5">unverified</span>
        {/if}
      </div>

      {#if email.verifiedAt}
        <button class="btn btn-xs" onclick={unverifyEmail(email.address)}>
          unverify
        </button>
      {:else}
        <button class="btn btn-xs" onclick={verifyEmail(email.address)}>
          verify
        </button>
      {/if}

      <button class="btn btn-xs" onclick={deleteEmail(email.address)}>
        <Trash size="14" />
      </button>
    </div>
  {/each}

  <div
    class="text-sm p-1.5 rounded-lg border-2 border-dashed border-neutral
    border-gray-300 flex items-center gap-1.5"
  >
    <label class="input input-xs input-ghost flex items-center gap-3 grow">
      <span class="label-text-alt opacity-75 whitespace-nowrap">new email</span>

      <div class="grow">
        <input
          type="text"
          class="w-full grow"
          placeholder="..."
          bind:value={address}
        />
      </div>
    </label>

    <button class="btn btn-xs btn-primary" onclick={addEmail}>
      <MailPlus size="14" />
    </button>
  </div>
</div>
