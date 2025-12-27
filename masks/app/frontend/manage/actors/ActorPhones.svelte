<script>
import _ from "lodash-es";
import { AlertTriangle, Trash2 as Trash } from "lucide-svelte";
import Alert from "@/components/Alert.svelte";
import PhoneInput from "@/components/PhoneInput.svelte";
import { mutationStore, gql, getContextClient } from "@urql/svelte";

let props = $props();
let graphql = getContextClient();
let actor = $state(props.actor);
let phones = $state(props.actor?.phones || []);
let saving = $state(false);
let errors = $state();

let save = (updates) => {
  saving = true;

  let update = mutationStore({
    client: graphql,
    query: gql`
        mutation ($input: PhoneInput!) {
          phone(input: $input) {
            phones {
              number
              verifiedAt
            }

            errors
          }
        }
      `,
    variables: { input: { ...updates, actorId: actor.id } },
  });

  update.subscribe((r) => {
    errors = r?.data?.phone?.errors;
    errors = errors?.length ? errors : null;
    saving = r?.fetching;

    if (!saving && !errors) {
      loading = false;
      phones = r.data?.phone?.phones;
    }
  });
};

let saveValues = (values) => {
  return () => {
    save(values);
  };
};

let number = $state("");

let addPhone = () => {
  save({ number, action: "create" });
};

let verifyPhone = (number) => {
  return () => {
    save({ number, action: "verify" });
  };
};

let unverifyPhone = (number) => {
  return () => {
    save({ number, action: "unverify" });
  };
};

let deletePhone = (number) => {
  return () => {
    if (confirm("Delete this phone number?")) {
      save({ number, action: "delete" });
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

  {#each phones as phone}
    <div class="flex items-center gap-1.5 text-sm pr-3 bg-base-100 rounded-lg">
      <PhoneInput value={phone.number} disabled />

      <button class="btn btn-xs" onclick={deletePhone(phone.number)}>
        <Trash size="14" />
      </button>
    </div>
  {/each}
</div>
