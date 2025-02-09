<script>
  import "web-streams-polyfill/polyfill";
  import * as WebAuthnJSON from "@github/webauthn-json/browser-ponyfill";

  import {
    Trash2 as Trash,
    Fingerprint,
    AlertTriangle,
    ChevronDown,
    Info,
  } from "lucide-svelte";

  import _ from "lodash-es";
  import { getContext, onMount } from "svelte";

  import Time from "@/components/Time.svelte";
  import Alert from "@/components/Alert.svelte";
  import Card from "@/components/Card.svelte";
  import AaguidIcon from "@/components/AaguidIcon.svelte";
  import Dropdown from "@/components/Dropdown.svelte";

  let { authorizing, authorize, ...props } = $props();

  let prompt = $state(props.prompt);
  let webauthnOpts = $state();
  let credential = $state();
  let credentials = $state();
  let empty = $derived(!credentials?.length);
  let existing = $state(false);

  let updateAuth = (r) => {
    prompt = r;
    webauthnOpts = prompt.auth?.extras?.webauthn;
    credentials = prompt.auth?.actor?.hardwareKeys;
    existing = false;

    if (authorizing && credentials) {
      credential = credentials[0];
    }
  };

  updateAuth(props.prompt);

  let create = (credential) => {
    authorize({
      event: prompt.verification("webauthn:create", { done: updateAuth }),
      updates: { create: credential },
    });
  };

  let destroy = (credential) => {
    return () => {
      authorize({
        event: prompt.verification("webauthn:delete", {
          webauthn: credential.name,
          done: updateAuth,
        }),
        updates: { delete: { id: credential.id } },
        done: updateAuth,
      });
    };
  };

  let setUp = () => {
    authorize({ event: "webauthn:register" }).then((p) => {
      webauthnOpts = p.extras.webauthn;
      existing = false;

      WebAuthnJSON.create(
        WebAuthnJSON.parseCreationOptionsFromJSON({ publicKey: webauthnOpts })
      )
        .then(create)
        .catch((e) => {
          if (e.code === e.INVALID_STATE_ERR) {
            existing = true;
          }
        });
    });
  };

  let challenge = () => {
    authorize({ event: "webauthn:challenge" }).then(updateAuth);
  };

  let authenticate = (credential) => {
    authorize({
      sudo: true,
      event: "webauthn:verify",
      updates: { webauthn: credential },
    }).then(updateAuth);
  };

  let verify = (opts) => {
    return () => {
      WebAuthnJSON.get(
        WebAuthnJSON.parseRequestOptionsFromJSON({ publicKey: opts })
      ).then(authenticate);
    };
  };

  onMount(() => {
    if (authorizing) {
      challenge();
    }
  });
</script>

{#if authorizing}
  <Alert type="secondary">
    <div class="flex items-center gap-1.5">
      <Dropdown value={credential} dropdownClass="-mt-0.5">
        {#snippet summary()}
          <summary class="btn btn-xs btn-neutral cols-1.5 mb-1.5">
            {#if credentials?.length > 1}
              {#each credentials as cred}
                <AaguidIcon icons={cred.icons} />
              {/each}

              <span class="pl-1.5">{credentials.length} keys</span>
              <ChevronDown size="16" />
            {:else}
              <AaguidIcon icons={credential?.icons} />

              <div class="truncate max-w-[175px] pl-1.5">
                {credential?.name}
              </div>
            {/if}
          </summary>
        {/snippet}

        {#snippet dropdown()}
          <div class="box py-1.5">
            {#if credentials?.length > 1}
              <ul class="">
                {#each credentials as c}
                  <li
                    class="p-1.5 flex items-center gap-3 text-sm font-bold text-neutral-content"
                  >
                    <AaguidIcon icons={c?.icons} />
                    <span class="truncate">{c.name}</span>
                  </li>
                {/each}
              </ul>
            {:else if !empty}
              <div class="text-xs whitespace-nowrap flex items-center gap-1.5">
                <Info size="16" />
                <span>
                  You added this key <Time timestamp={credential?.createdAt} />.
                </span>
              </div>
            {/if}
          </div>
        {/snippet}
      </Dropdown>
    </div>

    <button
      class="btn btn-secondary w-full btn-lg mb-1.5"
      disabled={!webauthnOpts}
      onclick={verify(webauthnOpts)}
    >
      <Fingerprint size="20" /> Verify
    </button>
  </Alert>
{:else}
  <Card>
    <div class="flex items-start gap-1.5">
      <div class="grow">
        <div class="flex items-center gap-3 grow py-1">
          <Fingerprint size="14" />
          <div class="grow">
            <div class="label-bold">Security key</div>
          </div>
        </div>

        {#if empty}
          <div class="text-sm opacity-75 mb-1.5">
            Add a hardware-based key, like a YubiKey or fingerprint sensor.
          </div>
        {/if}
      </div>
    </div>

    {#if existing}
      <Alert type="warn" icon={AlertTriangle}>
        You've already added this security key...
      </Alert>
    {/if}

    <div class="flex flex-col gap-1.5 my-1.5">
      {#if !empty}
        {#each credentials || [] as cred}
          <div class="bg-base-100 rounded-lg p-1.5">
            <div class="flex items-center gap-1.5">
              <div
                class="text-black dark:text-white grow ml-1.5 whitespace-nowrap"
              >
                {cred.name}
              </div>

              <span class="text-xs whitespace-nowrap opacity-75"
                ><Time ago="old" timestamp={cred.createdAt} /></span
              >

              <button
                type="button"
                class="btn btn-xs text-error m-0 p-0 px-1"
                onclick={destroy(cred)}
              >
                <Trash size="15" />
              </button>
            </div>
          </div>
        {/each}
      {/if}
    </div>

    <button type="button" class={"btn btn-sm w-full"} onclick={setUp}>
      {empty ? "Add your key" : "Add another key"}
    </button>
  </Card>
{/if}
