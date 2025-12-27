<script>
import _ from "lodash-es";
import { DoorOpen, Tickets, Fingerprint, KeySquare, User } from "lucide-svelte";
import Page from "./Page.svelte";
import ActorProfile from "./actors/ActorProfile.svelte";
import ActorSecondFactor from "./actors/ActorSecondFactor.svelte";
import ActorResult from "./ActorResult.svelte";
import TokenList from "./list/Token.svelte";
import { ActorFragment } from "@/lib";
import { mutationStore, queryStore, gql, getContextClient } from "@urql/svelte";
import { getContext } from "svelte";
import Tabs from "./Tabs.svelte";

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
  }),
);

let actor = $state();
let saving = $state(false);
let changes = $state({});
let errors = $state();
let original = $state(false);
let notFound = $state(false);
let { root } = getContext("page");

let path = $derived(`${root}/actor/${actor.id}`);

let subscribe = () => {
  query.subscribe((r) => {
    actor = r?.data?.actor;
    original = original || actor;

    if (r.data && r.data.actor === null) {
      notFound = true;
    }

    if (actor) {
      query.pause();
    }
  });
};

subscribe();

let save = (updates) => {
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

        ${ActorFragment}
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
    }
  });
};

let change = (obj) => {
  changes = { ...changes, ...obj };
  actor = { ...actor, ...changes };
};

let isChanged = () => {
  return !_.isEqual(original, actor);
};
</script>

<Page {...props} loading={!actor} {notFound}>
  <div class="flex flex-col gap-3">
    <ActorResult
      actor={original}
      isCurrent={props.actor.id == original.id}
      class="bg-base-100"
    />

    {#if actor}
      <Tabs
        goto
        useHash
        style="cards"
        tab="profile"
        props={{ actor, change }}
        tabs={{
          profile: {
            icon: User,
            name: "Profile",
            component: ActorProfile,
            href: `${path}`,
          },
          tokens: {
            icon: Tickets,
            name: "Tokens",
            component: TokenList,
            props: { variables: { actor: actor.identifier }, hideActor: true },
            href: `${path}#tokens`,
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
      </Tabs>
    {/if}
  </div>
</Page>
