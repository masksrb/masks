<script>
  import _ from "lodash-es";
  import {
    Info,
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
  import PasswordInput from "@/components/PasswordInput.svelte";
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

  let { change, ...props } = $props();
  let graphql = getContextClient();
  let actor = $state(props.actor);
  let saving = $state(false);
  let loading = $state(true);
  let errors = $state();

  let save = (updates) => {
    updates = updates;
    saving = true;

    let update = mutationStore({
      client: graphql,
      query: gql`
        mutation ($input: ActorInput!) {
          actor(input: $input) {
            actor {
              id
              password
              passwordChangeable
              passwordChangedAt
            }

            errors
          }
        }
      `,
      variables: { input: { ...updates, id: actor.id } },
    });

    update.subscribe((r) => {
      errors = r?.data?.actor?.errors;
      errors = errors?.length ? errors : null;
      saving = r?.fetching;

      if (!saving && !errors) {
        actor = r?.data?.actor?.actor;
        loading = false;
      }
    });
  };

  let deletePassword = () => {
    if (confirm("Are you sure you want to remove their password?")) {
      save({ resetPassword: true });
    }
  };
</script>

<PasswordInput
  onChange={(e) => change({ password: e.target.value })}
  inputClass="placeholder:opacity-50"
  placeholder={`enter a new password...`}
>
  {#snippet before()}
    <span class="label-text-alt opacity-75">password</span>
  {/snippet}

  {#snippet end()}
    {#if actor.password}
      <button class="btn btn-xs" onclick={deletePassword}>
        <Trash size="14" />
      </button>
    {/if}
  {/snippet}
</PasswordInput>

{#key actor.passwordChangedAt}
  <div class="flex items-center gap-1.5 pl-3 pt-1.5 text-xs">
    <Info size="12" />

    <span>
      {#if actor.password}
        {#if actor.passwordChangedAt}
          password last changed <Time timestamp={actor.passwordChangedAt} />...
        {:else}
          password never changed...
        {/if}
      {:else}
        password is currently blank. password-based login is disabled for this
        actor.
      {/if}
    </span>
  </div>
{/key}
