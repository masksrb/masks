<script module>
import { root } from "../lib/root.js";

const token = document.querySelector('meta[name="csrf-token"]')?.content ?? "";
</script>

<script>
let { actor, signOut = null } = $props();
</script>

<div class="actor">
  <img src={actor.avatar} width="44" height="44" alt="" class="avatar actor-avatar" />

  <div class="actor-who">
    <span class="actor-name">{actor.name}</span>

    {#if actor.details.length || actor.note}
      <span class="actor-sub">
        {actor.details.join(" · ")}
        {#if actor.note}
          <span class="actor-note">{actor.note}</span>
        {/if}
      </span>
    {/if}

    {#if actor.role}
      <span class="actor-role">{actor.role}</span>
    {/if}
  </div>

  {#if signOut}
    <form class="signout" method="post" action={`${root}/logout`}>
      <input type="hidden" name="authenticity_token" value={token} />
      <button type="submit" class="textlink">{signOut}</button>
    </form>
  {/if}
</div>
