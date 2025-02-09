<script>
  import _ from "lodash-es";
  import {
    Fingerprint,
    KeySquare,
    MonitorSmartphone,
    Handshake,
    LogIn,
    RotateCcw,
    MailPlus,
    Trash2 as Trash,
    User,
  } from "lucide-svelte";
  import Page from "./Page.svelte";
  import Alert from "@/components/Alert.svelte";
  import Time from "@/components/Time.svelte";
  import Avatar from "@/components/Avatar.svelte";
  import Identicon from "@/components/Identicon.svelte";
  import EditableImage from "@/components/EditableImage.svelte";
  import Actions from "./Actions.svelte";
  import ActorProfile from "./ActorProfile.svelte";
  import ActorSecondFactor from "./ActorSecondFactor.svelte";
  import ActorResult from "./ActorResult.svelte";
  import TokenList from "./list/Token.svelte";
  import { ActorFragment } from "@/util.js";
  import {
    mutationStore,
    queryStore,
    gql,
    getContextClient,
  } from "@urql/svelte";

  let { params, ...props } = $props();
  let graphql = getContextClient();

  let query = $derived(
    queryStore({
      client: getContextClient(),
      query: gql`
        query ($id: ID!) {
          actor(id: $id) {
            ...ActorFragment
          }
        }

        ${ActorFragment}
      `,
      variables: { id: params[0] },
      requestPolicy: "network-only",
    })
  );

  let result = $state({ data: {} });
  let actor = $state();
  let saving = $state(false);
  let changes = $state({});
  let errors = $state();
  let original = $state(false);
  let loading = $state(true);
  let notFound = $state(false);

  let subscribe = () => {
    query.subscribe((r) => {
      result = r;
      actor = r?.data?.actor;
      original = original || actor;
      loading = r.fetching;

      if (r.data && r.data.actor === null) {
        notFound = true;
        loading = false;
      }

      if (actor) {
        query.pause();
      }
    });
  };

  subscribe();

  let save = (updates) => {
    updates = updates || changes;
    saving = true;

    let update = mutationStore({
      client: graphql,
      query: gql`
        mutation ($input: ActorInput!) {
          actor(input: $input) {
            actor {
              ...ActorFragment
            }

            errors
          }
        }

        ${actorFragment}
      `,
      variables: { input: { ...updates, id: actor.id } },
    });

    update.subscribe((r) => {
      errors = r?.data?.actor?.errors;
      errors = errors?.length ? errors : null;
      saving = r?.fetching;

      if (!saving && !errors) {
        changes = {};
        original = actor = r?.data?.actor?.actor;
        loading = false;
      }
    });
  };

  let saveValues = (values) => {
    return () => {
      save(values);
    };
  };

  let change = (obj) => {
    changes = { ...changes, ...obj };
    actor = { ...actor, ...changes };
  };

  let isChanged = () => {
    return !_.isEqual(original, actor);
  };

  let reset = () => {
    errors = null;
    actor = original;
    changes = {};
  };

  let newEmail = $state("");

  let resetEmail = () => {
    newEmail = "";

    change({ createEmail: null });
  };

  let addEmail = () => {
    change({ createEmail: newEmail });
  };
</script>

<Page {...props} loading={!actor} {notFound}>
  <div class="flex flex-col gap-3">
    <ActorResult
      actor={original}
      isCurrent={props.actor.id == original.id}
      class="bg-base-100"
    />

    <Actions
      tab="profile"
      record={actor}
      {errors}
      tabs={{
        profile: {
          icon: User,
          name: "Profile",
          component: ActorProfile,
          props: { actor, change },
        },
        "second-factor": {
          icon: Fingerprint,
          name: "2FA",
          component: ActorSecondFactor,
          props: { actor, change },
        },
        tokens: {
          icon: KeySquare,
          name: "Tokens",
          component: TokenList,
          props: { variables: { actor: actor.identifier }, hideActor: true },
        },
      }}
    >
      {#snippet after()}
        <button
          class="btn btn-primary btn-sm"
          disabled={!isChanged()}
          onclick={(e) => save(changes)}
        >
          save
        </button>
      {/snippet}
    </Actions>
  </div>
</Page>
