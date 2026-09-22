<script>
import { initials, personFrom } from "../person.js";

let {
  account,
  avatarUrl = null,
  size = 44,
  onSignOut = null,
  signOutLabel = "Sign out",
  class: className = "",
} = $props();

const info = $derived(personFrom(account));

let broken = $state(null);
const showsAvatar = $derived(avatarUrl && broken !== avatarUrl);
</script>

<div class={["masks-person", className].filter(Boolean).join(" ")}>
  {#if showsAvatar}
    <img
      class="masks-person-avatar"
      src={avatarUrl}
      alt=""
      width={size}
      height={size}
      onerror={() => (broken = avatarUrl)}
    />
  {:else}
    <span
      class="masks-person-avatar masks-person-avatar-letters"
      style="width:{size}px;height:{size}px;font-size:{Math.round(size * 0.38)}px"
    >
      {initials(info.name)}
    </span>
  {/if}

  <div class="masks-person-who">
    <span class="masks-person-name">{info.name}</span>

    {#if info.details.length || info.unconfirmed}
      <span class="masks-person-sub">
        {info.details.join(" · ")}
        {#if info.unconfirmed}
          <span class="masks-person-note">unconfirmed</span>
        {/if}
      </span>
    {/if}

    {#if info.manager}
      <span class="masks-person-role">Manager</span>
    {/if}
  </div>

  {#if onSignOut}
    <button type="button" class="masks-person-signout" onclick={onSignOut}>
      {signOutLabel}
    </button>
  {/if}
</div>
