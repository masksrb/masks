<script>
  import _ from "lodash-es";
  import {
    Smartphone,
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
  import PhoneInput from "@/components/PhoneInput.svelte";
  import {
    mutationStore,
    queryStore,
    gql,
    getContextClient,
  } from "@urql/svelte";

  let props = $props();
  let graphql = getContextClient();
  let actor = $state(props.actor);
  let otpSecrets = $state(props.actor?.otpSecrets || []);
  let saving = $state(false);
  let loading = $state(true);
  let errors = $state();

  let save = (updates) => {
    updates = updates;
    saving = true;

    let update = mutationStore({
      client: graphql,
      query: gql`
        mutation ($input: OtpSecretInput!) {
          otpSecret(input: $input) {
            otpSecrets {
              id
              name
              createdAt
              verifiedAt
            }

            errors
          }
        }
      `,
      variables: { input: { ...updates, actorId: actor.id } },
    });

    update.subscribe((r) => {
      errors = r?.data?.otpSecret?.errors;
      errors = errors?.length ? errors : null;
      saving = r?.fetching;

      if (!saving && !errors) {
        loading = false;
        otpSecrets = r.data?.otpSecret?.otpSecrets;
      }
    });
  };

  let deleteOtpSecret = (id) => {
    return () => {
      if (confirm("Delete this TOTP secret?")) {
        save({ id, action: "delete" });
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

  {#each otpSecrets as otpSecret}
    <div
      class="flex items-center gap-1.5 text-sm pr-1.5 bg-base-100 rounded-lg p-1.5 pl-3"
    >
      {#if otpSecret.name}
        <span class="grow">{otpSecret.name}</span>
      {:else}
        <span class="grow opacity-75 italic">unnamed</span>
      {/if}

      <span class="text-xs opacity-75">
        <Time timestamp={otpSecret.createdAt} ago="old" />
      </span>

      <button class="btn btn-xs" onclick={deleteOtpSecret(otpSecret.id)}>
        <Trash size="14" />
      </button>
    </div>
  {/each}
</div>
