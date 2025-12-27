<script>
import _ from "lodash-es";
import {
  X,
  Star,
  CircleCheck,
  CircleMinus,
  Pen,
  Phone,
  PlusSquare,
  Smartphone,
  MessageSquare,
  SquareActivity,
  Mail,
  Upload,
  ImageUp,
  Check,
  Trash2,
} from "lucide-svelte";
import Mutation from "@/components/Mutation.svelte";
import PasswordInput from "@/components/PasswordInput.svelte";
import Alert from "@/components/Alert.svelte";
import { onMount } from "svelte";
import { gql } from "@urql/svelte";

const modules = import.meta.glob("./*.svelte");

let { settings, ...props } = $props();

let editing = $state();
let Component = $state();
let adding = $state();
let name = $state();
let error = $state();

let changes = $state({});
let original = $state({ ...props.adapter });
let adapter = $state({ ...original });
let config = $state({ ...adapter.config });

let change = (updates) => {
  changes = _.merge(changes, updates);
  adapter = { ...adapter, config: _.merge(adapter.config, changes) };
};

let reset = () => {
  adapter = { ...original };
  config = { ...adapter.config };
  changes = {};
};

let edit = async () => {
  editing = !editing;

  if (!Component) {
    Component = (await modules[`./${adapter.type}.svelte`]?.())?.default;
  }

  if (!editing) {
    reset();
  }
};

let update = gql`
    mutation ($input: AdapterInput!) {
      adapter(input: $input) {
        adapter {
          key
          name
          type
          setup
          primary
          deleted
          config
        }

        errors
      }
    }
  `;

onMount(() => {
  if (adapter?.primary) {
    edit();
  }
});

let onmutate = (result) => {
  if (result.adapter) {
    if (adding) {
      return window.location.reload();
    }

    original = result.adapter;

    reset();
  } else if (adding) {
    error = true;
  }
};

let changeName = (mut) => {
  return _.debounce(() => {
    mut({ key: adapter.key, name: adapter.name });
  }, 300);
};
</script>

{#if !adapter.deleted}
  <Mutation query={update} {onmutate} key="adapter">
    {#snippet children({ mutate })}
      {#if props.adapter}
        <div
          class={`box-snug ${adapter.setup ? "bg-base-300" : "bg-base-100"}`}
        >
          <div class="cols gap-0.5">
            <div class="mr-2.5">
              {#if adapter.primary}
                <Star size="18" class="text-warning" />
              {:else if adapter.setup}
                <CircleCheck size="18" class="text-success" />
              {:else}
                <CircleMinus size="18" class="opacity-50" />
              {/if}
            </div>

            <div class="rows grow">
              <input
                type="text"
                class="!outline-none bg-transparent text-sm font-bold grow"
                bind:value={adapter.name}
                oninput={changeName(mutate)}
              />
              <span class="label-xs font-mono text-[10px]">{adapter.type}</span>
            </div>

            {#if !adapter.setup && adapter.primary}
              <span class="label-xs text-warning">
                configuration required
              </span>
            {/if}

            <button class="btn btn-ghost btn-square btn-xs" onclick={edit}>
              {#if editing}
                <X size="14" />
              {:else}
                <Pen size="14" />
              {/if}
            </button>

            {#if !_.isEqual(adapter.config, config)}
              <button
                class="btn btn-xs btn-success btn-square"
                onclick={() => mutate({ key: adapter.key, config: changes })}
              >
                <Check size="14" />
              </button>
            {:else}
              <button
                class="btn btn-xs btn-ghost btn-square"
                onclick={() => mutate({ key: adapter.key, deleted: true })}
              >
                <Trash2 size="14" />
              </button>
            {/if}
          </div>

          {#if editing && Component}
            <div class="rows-3 my-2">
              <Component {adapter} {settings} {change} />
            </div>
          {/if}
        </div>
      {:else}
        <div class={`box-snug border-dotted border-base-300 border`}>
          <div class="cols-3">
            <PlusSquare class="label-xs" size="18" />

            <select
              class="select select-sm select-ghost !outline-none grow"
              onchange={(e) => (adding = e.target.value)}
            >
              <option class="text-neutral" disabled selected
                >{props.placeholder}</option
              >

              {#each _.filter(settings?.adapterTypes, props.filter) as type}
                <option value={type.type} selected={type.type == adding}
                  >{type.name}</option
                >
              {/each}
            </select>
          </div>

          {#if adding}
            <div class="cols-3 my-1.5">
              <input
                type="text"
                bind:value={name}
                class="input input-sm grow w-full"
                placeholder="Give it a name..."
              />

              <button
                onclick={() => mutate({ name, type: adding })}
                class={`btn btn-sm ${error ? "btn-error animate-denied" : name ? "btn-success" : ""}`}
                disabled={!name}
              >
                save
              </button>
            </div>
          {/if}
        </div>
      {/if}
    {/snippet}
  </Mutation>
{/if}
