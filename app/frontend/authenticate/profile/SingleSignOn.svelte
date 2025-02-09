<script>
  import ProviderIcon from "@/components/ProviderIcon.svelte";
  import Time from "@/components/Time.svelte";

  import { Link } from "lucide-svelte";

  let { sso, prompt, authorize, actor, ...props } = $props();

  let singleSignOn = (e) => {
    e.preventDefault();
    e.stopPropagation();

    return authorize({
      event: "sso:request",
      updates: { provider: sso.provider.id, origin: window.location.href },
    });
  };

  let destroy = (e) => {
    e.preventDefault();
    e.stopPropagation();

    return authorize({
      event: prompt.verification("sso:unlink", {
        provider: sso.provider.name,
      }),
      updates: { sso: sso.id },
    });
  };
</script>

<div
  class={`box border p-2 border-neutral border-opacity-50 dark:border-opacity-100 ${sso.createdAt ? "bg-opacity-50 border-0 bg-base-100 shadow" : "border-dashed"}`}
>
  <div class={`cols-3`}>
    <ProviderIcon
      provider={sso.provider}
      bg
      class="bg-neutral fill-white h-8 w-8 p-1 ml-0.5"
    />

    <div class="rows pr-1.5 grow">
      <p class="text-xs">{sso.provider.name}</p>
      <p
        class={sso.identifier
          ? "text-xs dark:text-white text-black"
          : "label-xs italic"}
      >
        {sso.identifier || "not linked..."}
      </p>
    </div>

    {#if sso.identifier}
      <div class="rows gap-0.5 items-end mr-0.5">
        <span class="label-xs">Linked <Time timestamp={sso.createdAt} /></span>

        {#if sso.deletable}
          <button class="underline text-xs font-bold" onclick={destroy}>
            Unlink
          </button>
        {/if}
      </div>
    {:else}
      <button class="btn btn-xs mr-1 btn-outline" onclick={singleSignOn}>
        <Link size="12" />
        Link
      </button>
    {/if}
  </div>
</div>
