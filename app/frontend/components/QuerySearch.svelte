<script>
  import { goto, query } from "@mateothegreat/svelte5-router";
  import Dropdown from "@/components/Dropdown.svelte";
  import {
    Filter,
    X,
    Search,
    ChevronDown,
    ChevronRight,
    ChevronUp,
  } from "lucide-svelte";

  let { keys, onquery, ...props } = $props();

  let url = $derived(props.url || window.location.pathname);
  let search = $state(
    Object.fromEntries(
      [...keys, ...Object.keys(props.toggle || {})].map((k) => {
        if (props.toggle?.[k]) {
          return [k, query(k) === "1" ? true : false];
        }

        return [k, query(k)];
      })
    )
  );

  onquery(search);

  let key = $state(props.key || keys.find((k) => query(k)) || keys[0]);

  let isEmpty = (u) => {
    return Object.values(u).filter(Boolean).length == 0;
  };

  let value = $state();

  let removeValue = (k) => {
    return (e) => {
      e.preventDefault();
      e.stopPropagation();

      doUpdate(k, null);
    };
  };

  let resetValues = (e) => {
    e.preventDefault();
    e.stopPropagation();

    goto(url);
  };

  let updateValue = (e) => {
    e.preventDefault();
    e.stopPropagation();

    doUpdate(key, value);
  };

  let doUpdate = (key, value) => {
    let qs = { ...search, [key]: value };

    qs = Object.entries(qs)
      .map(([k, v]) => {
        if (v) {
          return [k, v];
        }
      })
      .filter(Boolean);

    goto(url, Object.fromEntries(qs));
  };

  let updateKey = (k, setter) => {
    return (e) => {
      e.preventDefault();
      e.stopPropagation();

      setter(k);

      key = k;
    };
  };
</script>

<div class={props.class}>
  {#if props.editable}
    <form class={`flex items-center w-full join`} onsubmit={updateValue}>
      <label
        class={`input dark:input-bordered input-ghost input-sm !outline-none flex items-center gap-3 grow
        w-full
        join-item ${isEmpty(search) ? "" : "rounded-b-none"}`}
      >
        <button
          type="submit"
          class={`btn btn-xs rounded-lg -ml-2 ${
            value ? "btn-accent" : "btn-neutral"
          }`}
        >
          <Search size="14" />
        </button>

        <input
          type="text"
          class="grow min-w-0"
          bind:value
          placeholder={props.placeholder || "Filter..."}
        />

        <Dropdown
          value={key}
          class="dropdown-end"
          dropdownClass="-mr-3 !mt-1.5 rounded"
        >
          {#snippet summary({ value, open })}
            <summary
              class="badge badge-neutral rounded text-xs flex items-center gap-1
              -mr-1.5"
            >
              <span class="opacity-75">by</span>
              {value}

              {#if keys?.length > 1}
                {#if open}
                  <ChevronUp size="14" />
                {:else}
                  <ChevronDown size="14" />
                {/if}
              {/if}
            </summary>
          {/snippet}

          {#snippet dropdown({ setValue, value })}
            {#if keys.length > 1}
              <div class="flex flex-col items-start gap-1.5 m-1.5 min-w-[88px]">
                {#each keys as k}
                  {#if value != k}
                    <button
                      onclick={updateKey(k, setValue)}
                      type="button"
                      class="badge rounded text-xs
                  whitespace-nowrap w-full flex items-center gap-1
                  justify-start"><span class="opacity-75">by</span> {k}</button
                    >
                  {/if}
                {/each}
              </div>
            {/if}
          {/snippet}
        </Dropdown>
      </label>
    </form>
  {/if}

  {#if !isEmpty(search)}
    <div
      class="flex items-center gap-1.5 bg-base-300 px-3 py-1 rounded-b-lg
      border-t border-base-100 pl-1.5"
    >
      <span class="text-xs opacity-75 hidden"> filters </span>

      {#each Object.entries(search) as [key, data]}
        {#if data && !props.toggle?.[key]}
          <button
            type="button"
            onclick={removeValue(key)}
            class={`badge badge-neutral flex items-center gap-0 rounded
              max-w-[150px] overflow-hidden px-1.5`}
          >
            <span class="pr-1 text-error">
              <X size="12" />
            </span>
            <span class="text-xs opacity-75">{key}:</span>
            <span class="text-xs font-bold truncate">{data}</span>
          </button>
        {/if}
      {/each}
    </div>
  {/if}
</div>

{#each Object.entries(props?.toggle || {}) as [key, desc]}
  <label class="label cursor-pointer cols-3 -mt-3 mb-1.5">
    <input
      type="checkbox"
      class="toggle toggle-xs"
      checked={query(key) == "1"}
      onclick={(e) => doUpdate(key, query(key) == "1" ? "0" : "1")}
    />

    <span class="grow label-text-alt"> {desc} </span>
  </label>
{/each}

{#if props.loading}
  <div class="flex flex-col dark:opacity-25 opacity-10 gap-1.5 px-0.5 mb-3">
    <div class="skeleton h-6 w-full"></div>
    <div class="skeleton h-6 w-full"></div>
    <div class="skeleton h-6 w-full"></div>
    <div class="skeleton h-6 w-full"></div>
    <div class="skeleton h-6 w-full"></div>
    <div class="skeleton h-6 w-11/12"></div>
    <div class="skeleton h-6 w-10/12"></div>
    <div class="skeleton h-6 w-4/12"></div>
  </div>
{:else if props.empty}
  <div
    class="rounded-lg
    shadow-inner bg-base-100 bg-opacity-15 dark:bg-opacity-100
    p-10 flex
    items-center -mt-1.5 justify-center min-h-[200px] flex-col"
  >
    <p class="text-xs dark:text-neutral-content text-neutral-content font-bold">
      Nothing found...
    </p>

    {#if !isEmpty(search)}
      <button onclick={resetValues} class="btn btn-xs btn-link text-error px-0"
        >Clear filters...</button
      >
    {/if}
  </div>
{/if}
