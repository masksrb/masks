<script>
  import Icon from "@iconify/svelte";
  import ActorPassword from "./ActorPassword.svelte";
  import ActorEmails from "./ActorEmails.svelte";
  import ActorPhones from "./ActorPhones.svelte";
  import Time from "@/components/Time.svelte";
  import { iconifyProvider } from "@/util.js";

  let { actor, change } = $props();
</script>

<div class="flex flex-col gap-1.5 mb-1.5">
  <p class="grow font-bold">Profile</p>
  <label class="input input-bordered flex items-center gap-3">
    <span class="label-text-alt opacity-75">full name</span>

    <input
      type="text"
      class="grow"
      value={actor.name}
      placeholder="..."
      oninput={(e) => change({ name: e.target.value || null })}
    />
  </label>

  <label class="input input-bordered flex items-center gap-3">
    <span class="label-text-alt opacity-75">nickname</span>

    <input
      type="text"
      class="grow"
      value={actor.nickname}
      placeholder="..."
      oninput={(e) => change({ nickname: e.target.value || null })}
    />
  </label>

  <ActorPassword {actor} {change} />

  <span class="text-xs opacity-75 mt-3">Single sign-on</span>

  <div class="flex flex-wrap gap-3">
    {#each actor.singleSignOns as sso}
      <div class="flex items-center gap-3 bg-base-100 rounded-lg p-1.5 pr-3">
        <div class="w-10 h-10 bg-base-300 rounded-lg p-1.5">
          <Icon icon={iconifyProvider(sso.provider)} height="100%" />
        </div>

        <div class="flex flex-col gap-0.5">
          <span class="text-white font-bold text-sm">{sso.identifier}</span>

          <div class="flex items-baseline gap-1.5">
            <span class="text-xs">{sso.provider.name}</span>
            <p class="text-xs opacity-75">
              <Time timestamp={sso.createdAt} ago="old" />
            </p>
          </div>
        </div>
      </div>
    {/each}
  </div>

  <span class="text-xs opacity-75 mt-3">emails</span>

  <ActorEmails {actor} />
</div>
