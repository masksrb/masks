<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";
import Person from "../shared/Person.svelte";

let { login } = $props();

const organizations = $derived(login.auth.organizations ?? []);
const client = $derived(login.client?.name ?? "");
</script>

<Head
  {login}
  title={client ? login.t("title_to", { client }) : login.t("title")}
  lede={login.t("lede")}
/>

{#if login.auth.person}
  <Person person={login.auth.person} signOut={login.t("sign_out")} />
{/if}

<div class="providers">
  {#each organizations as organization (organization.key)}
    <Action
      {login}
      quiet
      label={login.t("as", { organization: organization.name, role: organization.role })}
      onclick={() => login.submit("organization", { organization: organization.key })}
    />
  {/each}
</div>
