<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";
import SetupSteps from "../shared/SetupSteps.svelte";

let { login } = $props();

const setup = $derived(login.auth.setup ?? {});
const names = $derived(setup.names ?? ["nickname", "email", "either"]);
const tenant = $derived(login.auth.tenant?.name ?? "");
const docs = $derived(login.auth.docs);
const manager = $derived(login.actor?.identifier ?? "");

let chosen = $state(setup.namedBy ?? "either");

const initial = (name) => (name ? name.trim().slice(0, 1).toUpperCase() : "");

function onsubmit(event) {
  event.preventDefault();

  if (!login.loading) {
    login.submit("setup-configure", { named_by: chosen });
  }
}
</script>

<div class="setup flow setup-ready">
  <div class="auth-pair">
    <span class="auth-mark auth-mark-client" aria-hidden="true"
      >{initial(manager)}</span>
    <span class="auth-wire"></span>
    <span class="auth-mark" aria-hidden="true">{initial(tenant)}</span>
  </div>

  <Head {login} title={login.t("title")} name={tenant} cap={login.t("cap")} />

  <SetupSteps {login} at={3} />

  <form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
    <div class="slab">
      <fieldset class="ledger-row">
        <legend class="ledger-label">{login.t("named_by")}</legend>

        <div class="check-set">
          {#each names as name (name)}
            <label class="check">
              <input
                type="radio"
                name="named_by"
                value={name}
                bind:group={chosen}
              />
              <span>{login.t(`named_by_${name}`)}</span>
            </label>
          {/each}
        </div>

        <span class="field-hint">{login.t("managers")}</span>
      </fieldset>
    </div>

    <Action
      {login}
      type="submit"
      busy={login.loading}
      label={login.t("submit")}
      working={login.t("working")}
    />
  </form>

  <p class="aside">
    {login.t("once")}
    {#if docs}
      <a class="textlink" href={docs} rel="noopener" target="_blank"
        >{login.t("docs")}</a
      >
    {/if}
  </p>
</div>
