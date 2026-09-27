<script>
import Head from "../shared/Head.svelte";
import Person from "../shared/Person.svelte";

let { login } = $props();

let chosen = $state(null);

const organizations = $derived(login.auth.organizations ?? []);
const client = $derived(login.client?.name ?? "");

const initials = (name) =>
  name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word[0])
    .join("")
    .toUpperCase();

async function choose(organization) {
  chosen = organization.key;

  try {
    await login.submit("organization", { organization: organization.key });
  } finally {
    chosen = null;
  }
}
</script>

<Head
  {login}
  title={client ? login.t("title_to", { client }) : login.t("title")}
  lede={login.t("lede")}
/>

{#if login.auth.person}
  <Person person={login.auth.person} signOut={login.t("sign_out")} />
{/if}

<ul class="org-picks" aria-label={login.t("title")}>
  {#each organizations as organization (organization.key)}
    <li>
      <button
        type="button"
        class="org-pick"
        disabled={login.loading}
        aria-busy={chosen === organization.key || undefined}
        aria-label={login.t("as", { organization: organization.name, role: organization.role })}
        onclick={() => choose(organization)}
      >
        <span class="org-pick-mark" aria-hidden="true">{initials(organization.name)}</span>
        <span class="org-pick-name">{organization.name}</span>
        <span class="org-pick-role">{chosen === organization.key ? login.t("working") : organization.role}</span>
      </button>
    </li>
  {/each}
</ul>
