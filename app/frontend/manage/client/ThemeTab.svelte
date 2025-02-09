<script>
  import EditableImage from "@/components/EditableImage.svelte";
  import { Trash2, Pencil, Upload, X, Check } from "lucide-svelte";
  import { getContext } from "svelte";
  import { gql } from "@urql/svelte";

  let { save, client, change, ...props } = $props();
  let { root } = getContext("page");
  let input = $state({});
  let editing = $state();

  let setFile = (e) => {
    input = { ...input, styles: e.target.files[0] };
  };
</script>

<div class="cols-3 mb-3">
  <EditableImage
    disabled={props.disabled}
    endpoint={`${root}/upload/client`}
    params={{ client_id: client.id }}
    src={client.logo}
    class="w-14 h-14"
  />

  <div class="rows-1.5">
    <span class="font-bold text-sm">Logo</span>
    <span class="label-xs">This image is shown during log in or sign up.</span>
  </div>
</div>

<div class="divider my-0 mb-2"></div>

<div class="flex flex-col gap-1.5">
  <p class="font-bold text-xs">Custom css</p>
  {#if client.stylesUrl}
    <div class="cols-3 box-snug bg-base-100">
      <p class="label-xs">URL</p>
      <a
        href={client.stylesUrl}
        target="_blank"
        class="truncate font-mono text-sm underline grow">{client.stylesUrl}</a
      >

      <button
        onclick={() => (editing = !editing)}
        class="btn btn-xs btn-ghost btn-square -mr-1.5"
        >{#if editing}<X size="14" />{:else}<Pencil size="14" />{/if}</button
      >

      <button
        onclick={() => save({ removeStyles: true })}
        class="btn btn-square btn-xs text-error btn-ghost"
        ><Trash2 size="14" /></button
      >
    </div>
  {/if}

  {#if editing || !client.stylesUrl}
    <div class="mt-1.5 rows-1.5">
      {#if !input.stylesUrl}
        <div class="cols-1.5">
          <input
            bind:value={input.stylesFile}
            type="file"
            class="grow w-full file-input file-input-sm"
            accept=".css"
            onchange={setFile}
          />
          {#if input.styles}
            <button
              onclick={() => save({ id: client.id, styles: input.styles })}
              disabled={!input?.styles}
              class="btn btn-square btn-success btn-sm"
              ><Upload size="20" /></button
            >

            <button
              onclick={() => (input = {})}
              class="btn btn-sm btn-square btn-error"><X /></button
            >
          {/if}
        </div>
      {/if}

      {#if !input.styles}
        {#if !input.stylesUrl}
          <div class="divider my-0 label-xs">or</div>
        {/if}

        <div class="cols-1.5">
          <label class="input input-sm">
            <input
              bind:value={input.stylesUrl}
              type="text"
              placeholder="Enter a custom URL..."
            />
            <span>.css only</span>
          </label>
          {#if input.stylesUrl}
            <button
              onclick={() => save({ stylesUrl: input.stylesUrl })}
              disabled={!input?.stylesUrl}
              class="btn btn-square btn-success btn-sm"
              ><Check size="20" /></button
            >

            <button
              onclick={() => (input = {})}
              class="btn btn-sm btn-square btn-error"><X /></button
            >
          {/if}
        </div>
      {/if}
    </div>
  {/if}
</div>
