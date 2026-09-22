<script module>
import { root } from "../lib/root.js";

const token = document.querySelector('meta[name="csrf-token"]')?.content ?? "";
</script>

<script>
let { person, signOut = null } = $props();
</script>

<div class="person">
  <img src={person.avatar} width="44" height="44" alt="" class="avatar person-avatar" />

  <div class="person-who">
    <span class="person-name">{person.name}</span>

    {#if person.details.length || person.note}
      <span class="person-sub">
        {person.details.join(" · ")}
        {#if person.note}
          <span class="person-note">{person.note}</span>
        {/if}
      </span>
    {/if}

    {#if person.role}
      <span class="person-role">{person.role}</span>
    {/if}
  </div>

  {#if signOut}
    <form class="signout" method="post" action={`${root}/logout`}>
      <input type="hidden" name="authenticity_token" value={token} />
      <button type="submit" class="textlink">{signOut}</button>
    </form>
  {/if}
</div>
