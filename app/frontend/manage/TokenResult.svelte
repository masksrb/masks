<script>
  import { TokenFragment } from "@/lib";
  import { route } from "@mateothegreat/svelte5-router";
  import { X, LogIn, User, Handshake, ChevronDown } from "lucide-svelte";
  import DeviceIcon from "@/components/DeviceIcon.svelte";
  import Identicon from "@/components/Identicon.svelte";
  import Time from "@/components/Time.svelte";
  import { gql } from "@urql/svelte";
  import CopyText from "@/components/CopyText.svelte";
  import Mutation from "@/components/Mutation.svelte";
  import Deletion from "./Deletion.svelte";
  import { getContext } from "svelte";

  let { root } = getContext("page");

  const TokenMutation = gql`
    mutation ($input: TokenInput!) {
      token(input: $input) {
        token {
          ...TokenFragment
        }
        errors
      }
    }

    ${TokenFragment}
  `;

  let { token, ...props } = $props();
  let opened = $state(props.open);
  let device = (token) => {
    return token.device || (props?.device?.type ? props.device : null);
  };

  let ICONS = {
    "Internal token": {
      icon: LogIn,
      cls: "bg-emerald-800 text-emerald-300",
    },
    "Access token": {
      icon: User,
      cls: "bg-lime-800 text-lime-200",
    },
    "Client token": {
      icon: Handshake,
      cls: "bg-cyan-800 text-cyan-200",
    },
  };
</script>

{#key token?.id}
  <Deletion
    type="Token"
    id={token.id}
    confirm="Are you sure you want to delete this token?"
  >
    {#snippet children({ deletion, deleting, deleted, errors })}
      <div class={`bg-base-100 rounded-lg px-3 max-w-full ${props.class}`}>
        <div class="flex items-center gap-3 w-full">
          {#if ICONS[token.type]}
            {@const Icon = ICONS[token.type].icon}
            {@const cls = token.revokedAt
              ? "bg-amber-800 text-amber-200"
              : ICONS[token.type].cls}
            <div
              class={`my-1 -ml-2 h-7 w-7 rounded-lg flex items-center justify-center ${cls}`}
            >
              <Icon size="20" />
            </div>
          {/if}

          {#if props.link}
            <a
              href={`${root}/tokens?id=${token.id}`}
              class={`truncate cols-1.5 items-baseline`}
            >
              {#if token.name}
                <b>
                  {token.name}
                </b>
              {/if}

              <span
                class={`truncate font-mono label-xs max-w-[60px] md:max-w-[160px]`}
              >
                {token.secret}
              </span>
            </a>
          {:else}
            <span class={`truncate cols-1.5 items-baseline`}>
              {#if token.name}
                <b>
                  {token.name}
                </b>
              {/if}

              <span
                class={`truncate font-mono label-xs max-w-[60px] md:max-w-[160px]`}
              >
                {token.secret}
              </span>
            </span>
          {/if}
          {#if !props.hideClient && token?.client}
            <a
              use:route
              class="truncate text-sm hover:underline focus:underline py-[8px]"
              href={`${root}/client/${token.client.id}`}
              >{token.client.name || token.client.id}</a
            >
          {/if}

          {#if token.actor && !props.hideActor}
            <a
              use:route
              href={`${root}/actor/${token.actor.id}`}
              class="
            truncate
            flex items-center gap-1.5
            hover:underline focus:underline"
            >
              <div class="min-w-5 w-5 h-5 bg-black rounded p-[1px] my-1.5 mr-1">
                <Identicon id={token.actor.identiconId} />
              </div>

              <b class="text-xs md:block hidden"
                >{token.actor.name || token.actor.identifier}</b
              >
            </a>
          {/if}

          <div class="grow"></div>

          <div class="flex items-center gap-3">
            <div class={`truncate text-xs opacity-75 flex items-center gap-3`}>
              <span
                class={`${deleted || token.expired ? "text-error" : token.revokedAt ? "text-warning" : "text-success"} opacity-75`}
              >
                {#if deleted}
                  deleted
                {:else if token.usable}
                  expires
                  <Time relative timestamp={token.expiresAt} />
                {:else if token.expired}
                  expired
                  <Time relative timestamp={token.expiresAt} />
                {:else if token.revokedAt}
                  revoked
                  <Time relative timestamp={token.revokedAt} />
                {/if}
              </span>
            </div>

            {#if !props.open && !props.link}
              <button
                class="btn btn-xs btn-square"
                onclick={() => (opened = !opened)}
              >
                {#if opened}
                  <X size="14" />
                {:else}
                  <ChevronDown size="14" />
                {/if}
              </button>
            {/if}
          </div>
        </div>

        {#if opened}
          <div class="-my-1.5 pb-3">
            <div class="divider my-0"></div>

            <div
              class="flex items-center gap-1.5 w-full mb-1.5 bg-base-300 p-1.5 pl-3 rounded-lg"
            >
              <div class="truncate text-xs opacity-75 grow">
                {token.type} created <Time
                  relative
                  timestamp={token.createdAt}
                />
              </div>

              {#if !deleted && !token.expired}
                <Mutation
                  key="token"
                  query={TokenMutation}
                  input={{ id: token.id }}
                  confirm={`Are you sure you want to ${token.revokedAt ? "restore" : "revoke"} this token?`}
                >
                  {#snippet children({ mutate, mutating })}
                    <button
                      class={`btn btn-xs ${token.revokedAt ? "btn-neutral" : "btn-warning"}`}
                      onclick={() =>
                        mutate({ revoked: token.revokedAt ? false : true })}
                    >
                      {token.revokedAt ? "restore" : "revoke"}
                    </button>
                  {/snippet}
                </Mutation>
              {/if}

              <button
                class="btn btn-xs btn-error"
                onclick={deletion}
                disabled={deleting || deleted}
              >
                {#if deleting}
                  <span class="loading loading-spinnner"></span>
                {:else if deleted}
                  deleted
                {:else}
                  delete
                {/if}
              </button>
            </div>

            <div class="flex flex-col gap-1.5 p-1.5">
              {#if device(token)}
                <a
                  class="cols gap-2 token text-xs"
                  use:route
                  title={`${device(token).name} on ${device(token).os}`}
                  href={`${root}/device/${device(token).id}`}
                >
                  <DeviceIcon
                    size="12"
                    device={device(token)}
                    class="opacity-50"
                  />

                  <span class="label-xs min-w-[60px]">device</span>

                  {`${device(token).name} on ${device(token).os}`}
                </a>
              {/if}

              {#if token.name}
                <CopyText
                  labelClass="min-w-[60px]"
                  label="name"
                  text={token.name}
                />
              {/if}
              {#if token.id}
                <CopyText
                  labelClass="min-w-[60px]"
                  label="identifier"
                  text={token.id}
                />
              {/if}
              {#if token.secret}
                <CopyText
                  labelClass="min-w-[60px]"
                  label="secret"
                  text={token.secret}
                />
              {/if}
              {#if token.redirectUri}
                <CopyText
                  labelClass="min-w-[60px]"
                  label="redirect"
                  text={token.redirectUri}
                />
              {/if}
              {#if token.scopes?.length}
                <CopyText
                  labelClass="min-w-[60px]"
                  label="scopes"
                  text={token.scopes.join(" ")}
                />
              {/if}

              {#if token.nonce}
                <CopyText
                  labelClass="min-w-[60px]"
                  label="nonce"
                  text={token.nonce}
                />
              {/if}
            </div>
          </div>
        {/if}
      </div>
    {/snippet}
  </Deletion>
{/key}
