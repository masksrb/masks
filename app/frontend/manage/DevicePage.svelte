<script>
  import { copy } from "svelte-copy";
  import _ from "lodash-es";
  import {
    Ban,
    Check,
    CircleSlash,
    CirclePause,
    CirclePlay,
    ClipboardX,
    ClipboardCheck,
    ClipboardCopy,
    LogOut,
    RotateCcw,
    MailPlus,
    Trash2 as Trash,
    User,
  } from "lucide-svelte";
  import Page from "./Page.svelte";
  import CopyButton from "@/components/CopyButton.svelte";
  import Alert from "@/components/Alert.svelte";
  import Time from "@/components/Time.svelte";
  import Identicon from "@/components/Identicon.svelte";
  import DeviceIcon from "@/components/DeviceIcon.svelte";
  import Mutation from "@/components/Mutation.svelte";
  import Deletion from "./Deletion.svelte";
  import ActorList from "./list/Actor.svelte";
  import ClientList from "./list/Client.svelte";
  import TokenList from "./list/Token.svelte";
  import { DeviceFragment } from "@/util.js";
  import {
    mutationStore,
    queryStore,
    gql,
    getContextClient,
  } from "@urql/svelte";

  let { params, ...props } = $props();
  let graphql = getContextClient();
  let DevicePageFragment = gql`
    fragment DevicePageFragment on Device {
      ...DeviceFragment

      tokens {
        type
        secret
        scopes
        actor {
          id
          name
          identifier
          identiconId
        }
        client {
          id
          name
        }
        createdAt
        expiresAt
      }
    }

    ${DeviceFragment}
  `;
  let query = $derived(
    queryStore({
      client: getContextClient(),
      query: gql`
        query ($id: ID!) {
          device(id: $id) {
            ...DevicePageFragment
          }
        }

        ${DevicePageFragment}
      `,
      variables: { id: params[0] },
      requestPolicy: "network-only",
    })
  );

  let result = $state({ data: {} });
  let device = $state();
  let saving = $state(false);
  let changes = $state({});
  let errors = $state();
  let original = $state(false);
  let loading = $state(true);
  let notFound = $state(false);

  let subscribe = () => {
    query.subscribe((r) => {
      result = r;
      device = r?.data?.device;
      original = original || device;
      loading = r.fetching;

      if (r.data && r.data.device === null) {
        notFound = true;
        loading = false;
      }

      if (device) {
        query.pause();
      }
    });
  };

  subscribe();

  let deviceMutation = gql`
    mutation ($input: DeviceInput!) {
      device(input: $input) {
        device {
          ...DevicePageFragment
        }

        errors
      }
    }

    ${DevicePageFragment}
  `;

  let loggedOut = $state();

  let onlogout = (result) => {
    device = result.data.device.device;
    loggedOut = true;
  };

  let onblock = (result) => {
    device = result.data.device.device;
  };

  let save = (updates) => {
    updates = updates || changes;
    saving = true;

    let update = mutationStore({
      client: graphql,
      query: gql`
        mutation ($input: DeviceInput!) {
          device(input: $input) {
            device {
              ...DeviceFragment
            }

            errors
          }
        }

        ${deviceFragment}
      `,
      variables: { input: { ...updates, id: device.id } },
    });

    update.subscribe((r) => {
      errors = r?.data?.device?.errors;
      errors = errors?.length ? errors : null;
      saving = r?.fetching;

      if (!saving && !errors) {
        changes = {};
        original = device = r?.data?.device?.device;
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
    device = { ...device, ...changes };
  };

  let isChanged = () => {
    return !_.isEqual(original, device);
  };

  let reset = () => {
    errors = null;
    device = original;
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

<Page {...props} loading={!device} {notFound}>
  <Deletion
    type="Device"
    id={device.id}
    confirm="Are you sure you want to delete this device?"
  >
    {#snippet children({ deletion, deleting, deleted, errors })}
      <div class={"mb-1.5 bg-base-100 rounded-lg p-3 py-1.5"}>
        <div class="flex items-center gap-3 w-full">
          <div class="px-1.5 relative">
            <DeviceIcon {device} size="28" />
          </div>

          <div class="grow max-w-full overflow-hidden flex flex-col mb-1">
            <div class="flex items-baseline gap-1.5">
              <span class="whitespace-nowrap font-bold" alt={device.userAgent}
                >{device.name} on {device.os}</span
              >
              <span class="opacity-75 text-xs">@</span>
              <span class="text-sm font-mono grow">{device.ip}</span>
            </div>

            <div class="flex items-center gap-1.5">
              <span class="whitespace-nowrap text-xs opacity-75"
                ><Time relative timestamp={device.createdAt} ago="old" />.</span
              >
              {#if device.blockedAt}
                <span class="whitespace-nowrap text-xs text-error"
                  >blocked <Time
                    relative
                    timestamp={device.blockedAt}
                  />...</span
                >
              {/if}
            </div>
          </div>
        </div>
      </div>

      <div class="flex items-center gap-1.5 mb-3">
        <label
          class="input input-bordered min-w-0 input-sm flex items-center gap-3"
        >
          <span class="label-text-alt opacity-75">ID</span>

          <input disabled type="text" class="min-w-0 grow" value={device.id} />

          <CopyButton
            class={`-mr-1.5 btn btn-xs btn-square btn-neutral`}
            value={device.id}
          />
        </label>

        <label
          class="input input-bordered input-sm min-w-0 flex items-center gap-3
      grow"
        >
          <span
            class="label-text-alt opacity-75 whitespace-nowrap md:hidden"
            title="User agent">UA</span
          >
          <span
            class="label-text-alt opacity-75 whitespace-nowrap hidden
            md:block">User Agent</span
          >

          <input
            disabled
            type="text"
            class="grow min-w-0"
            value={device.userAgent}
          />

          <CopyButton
            class={`-mr-1.5 btn btn-xs btn-square btn-neutral`}
            value={device.userAgent}
          />
        </label>

        <label
          class="input input-bordered input-sm max-w-[120px] min-w-0 flex items-center gap-3"
        >
          <span class="label-text-alt opacity-75">Ver.</span>

          <input
            disabled
            type="text"
            class="grow min-w-0"
            value={device.version}
          />

          <CopyButton
            class={`-mr-1.5 btn btn-xs btn-square btn-neutral`}
            value={device.version}
          />
        </label>
      </div>

      <div class="mb-3 bg-neutral rounded-lg p-3">
        <div class="pl-1.5 mb-3 font-bold text-xs">recent tokens</div>

        <TokenList variables={{ device: device.id }} />
      </div>

      <Alert type="gray" class="mb-3">
        <div class="flex flex-col gap-3">
          <div class="flex items-center gap-3 w-full">
            <Ban class="text-error" size="16" />

            {#if device.blockedAt}
              <p class="grow">
                <b>Device blocked</b>. Future sessions will be denied.
              </p>
            {:else}
              <p class="grow">Block future sessions on this device...</p>
            {/if}

            <Mutation
              key="device"
              query={deviceMutation}
              onmutate={onblock}
              input={{
                id: device.id,
                block: device.blockedAt ? false : true,
                unblock: device.blockedAt ? true : false,
              }}
            >
              {#snippet children({ mutate, mutating })}
                <button
                  class="btn btn-sm"
                  onclick={mutate}
                  disabled={deleting || deleted || mutating}
                >
                  {device.blockedAt ? "unblock" : "block"}
                </button>
              {/snippet}
            </Mutation>
          </div>
          <div class="flex items-center gap-3 w-full">
            <LogOut class="text-warning" size="16" />

            <p class="grow text-left">
              {#if loggedOut}
                <b>Sessions expired.</b> You can try again later...
              {:else}
                Expire all sessions associated with this device...
              {/if}
            </p>

            <Mutation
              key="device"
              query={deviceMutation}
              onmutate={onlogout}
              input={{
                id: device.id,
                rotate: true,
              }}
            >
              {#snippet children({ mutate, mutating })}
                <button
                  class="btn btn-sm"
                  onclick={mutate}
                  disabled={deleting || deleted || mutating || loggedOut}
                  >expire</button
                >
              {/snippet}
            </Mutation>
          </div>

          <div class="flex items-center gap-3">
            <Trash class={deleted ? "text-error" : "opacity-75"} size="16" />

            <p class="grow">
              {#if deleted}
                <b>Device deleted.</b> Associated sessions will expire shortly...
              {:else}
                Delete this device and associated sessions...
              {/if}
            </p>

            <button
              class="btn btn-sm"
              onclick={deletion}
              disabled={deleting || deleted}
            >
              {#if deleting}
                <span class="loading loading-spinnner"></span>
              {:else}
                delete
              {/if}
            </button>
          </div>
        </div>
      </Alert>
    {/snippet}
  </Deletion>
</Page>
