<script>
import { actorFrom, initials } from "../actor.js";

let {
  account,
  avatarUrl = null,
  size = 44,
  onSignOut = null,
  signOutLabel = "Sign out",
  onSwitchOrganization = null,
  class: className = "",
} = $props();

const info = $derived(actorFrom(account));

let broken = $state(null);
const showsAvatar = $derived(avatarUrl && broken !== avatarUrl);
</script>

<div class={["masks-actor", className].filter(Boolean).join(" ")}>
  {#if showsAvatar}
    <img
      class="masks-actor-avatar"
      src={avatarUrl}
      alt=""
      width={size}
      height={size}
      onerror={() => (broken = avatarUrl)}
    />
  {:else}
    <span
      class="masks-actor-avatar masks-actor-avatar-letters"
      style="width:{size}px;height:{size}px;font-size:{Math.round(size * 0.38)}px"
    >
      {initials(info.name)}
    </span>
  {/if}

  <div class="masks-actor-who">
    <span class="masks-actor-name">{info.name}</span>

    {#if info.details.length || info.unconfirmed}
      <span class="masks-actor-sub">
        {info.details.join(" · ")}
        {#if info.unconfirmed}
          <span class="masks-actor-note">unconfirmed</span>
        {/if}
      </span>
    {/if}

    {#if info.organization}
      <span class="masks-actor-org">
        {info.organization.name}
        <span class="masks-actor-org-role">{info.role}</span>
      </span>
    {/if}

    {#if info.manager}
      <span class="masks-actor-role">Manager</span>
    {/if}

    {#if onSwitchOrganization && info.others.length}
      <span class="masks-actor-orgs">
        {#each info.others as other (other.key)}
          <button
            type="button"
            class="masks-actor-switch"
            onclick={() => onSwitchOrganization(other.key)}
          >
            {other.name}
          </button>
        {/each}
      </span>
    {/if}
  </div>

  {#if onSignOut}
    <button type="button" class="masks-actor-signout" onclick={onSignOut}>
      {signOutLabel}
    </button>
  {/if}
</div>
