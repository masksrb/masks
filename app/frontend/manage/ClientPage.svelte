<script>
  import _ from "lodash-es";
  import {
    Info,
    X,
    Share2,
    Fingerprint,
    Check,
    Palette,
    AlertTriangle as AlertIcon,
    KeySquare,
    Cog,
  } from "lucide-svelte";
  import Page from "./Page.svelte";
  import ClientResult from "./ClientResult.svelte";

  import EditableImage from "@/components/EditableImage.svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import Time from "@/components/Time.svelte";
  import Actions from "./Actions.svelte";
  import ActorList from "./list/Actor.svelte";
  import TokenList from "./list/Token.svelte";
  import ThemeTab from "./client/ThemeTab.svelte";
  import GeneralTab from "./client/GeneralTab.svelte";
  import {
    mutationStore,
    queryStore,
    gql,
    getContextClient,
  } from "@urql/svelte";
  import { ClientFragment } from "@/util.js";

  let { params, grapqhl, ...props } = $props();
  let graphql = getContextClient();
  let query = $derived(
    queryStore({
      client: graphql,
      query: gql`
        query ($id: ID!) {
          client(id: $id) {
            ...ClientFragment
          }
          install {
            clients
          }
        }

        ${ClientFragment}
      `,
      variables: { id: params[0] },
      requestPolicy: "network-only",
    })
  );

  let saving = $state(false);

  let save = () => {
    query.pause();

    saving = true;

    let update = mutationStore({
      client: graphql,
      query: gql`
        mutation ($input: ClientInput!) {
          client(input: $input) {
            client {
              ...ClientFragment
            }

            errors
          }
        }

        ${ClientFragment}
      `,
      variables: { input: { ...changes, id: client.id } },
    });

    update.subscribe((r) => {
      errors = r?.data?.client?.errors;
      errors = errors?.length ? errors : null;
      saving = r?.fetching;

      if (!saving && !errors) {
        changes = {};
        original = client = r?.data?.client?.client;
        loading = false;
      }
    });
  };

  let result = $state({ data: {} });
  let client = $state();
  let settings = $derived(result?.data?.install);
  let changes = $state({});
  let errors = $state();
  let original = $state(false);
  let loading = $state(true);

  let subscribe = () => {
    query.subscribe((r) => {
      result = r;
      client = r?.data?.client;
      original = original || client;
      loading = r.fetching;
    });
  };

  subscribe();

  let change = (obj) => {
    changes = { ...changes, ...obj };
    client = { ...client, ...changes };
  };

  let isChanged = () => {
    return !_.isEqual(original, client);
  };

  let reset = () => {
    errors = null;
    client = original;
    changes = {};
  };

  let subjectTypes = {
    "public-uuid": {
      name: "UUID",
      desc: "Actors are distinguished by a globally unique ID...",
    },
    "public-identifier": {
      name: "Identifier",
      desc: "Actor IDs will include their unique nickname or login email...",
    },
    "pairwise-uuid": {
      name: "Masked UUID",
    },
  };
</script>

{#key client?.updatedAt}
  <Page {...props} loading={loading || !client}>
    <ClientResult {client} {change} class="mb-3">
      {#snippet after()}
        <div class="flex flex-col items-center pr-1.5">
          <button
            class="btn btn-sm btn-success"
            disabled={saving || loading || !isChanged()}
            type="button"
            onclick={save}><Check size="20" /></button
          >
          <button
            class={`btn btn-xs text-error btn-link ${isChanged() ? "" : "opacity-0"}`}
            type="button"
            disabled={!isChanged()}
            onclick={reset}>reset</button
          >
        </div>
      {/snippet}
    </ClientResult>

    <Actions
      tab="general"
      record={client}
      {errors}
      tabs={{
        general: {
          icon: Cog,
          name: "settings",
          component: GeneralTab,
          props: { settings, client, change },
        },
        theme: {
          icon: Palette,
          name: "theme",
          component: ThemeTab,
          props: { client, change },
        },
        tokens: {
          icon: KeySquare,
          name: "tokens",
          component: TokenList,
          props: { variables: { client: client.id }, hideClient: true },
        },
      }}
    />
  </Page>
{/key}
