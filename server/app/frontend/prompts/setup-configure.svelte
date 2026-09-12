<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";
import SetupSteps from "../shared/SetupSteps.svelte";

let { login } = $props();

const setup = $derived(login.auth.setup ?? {});
const names = $derived(setup.names ?? ["nickname", "email", "either"]);
const offers = ["off", "anything", "bounded"];
const tenant = $derived(login.auth.tenant?.name ?? "");
const docs = $derived(login.auth.docs);
const manager = $derived(login.actor?.identifier ?? "");
const origin = typeof location === "undefined" ? "" : location.origin;

let called = $state(setup.called ?? "");
let chosen = $state(setup.namedBy ?? "either");
let registration = $state(setup.registration ?? "bounded");
let scopes = $state(setup.registrationScopes ?? "");

const initial = (name) => (name ? name.trim().slice(0, 1).toUpperCase() : "");

const ready = $derived(
  called.trim().length > 0 &&
    (registration !== "bounded" || scopes.trim().length > 0),
);

function onsubmit(event) {
  event.preventDefault();

  if (ready && !login.loading) {
    login.submit("setup-configure", {
      named_by: chosen,
      called,
      registration,
      registration_scopes: scopes,
    });
  }
}
</script>

<div class="setup flow" class:setup-ready={ready}>
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
      <label class="ledger-row">
        <span class="ledger-label">{login.t("called")}</span>
        <input type="text" name="called" class="control" bind:value={called} />
        <span class="field-hint">{login.t("called_hint")}</span>
      </label>

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

      <fieldset class="ledger-row">
        <legend class="ledger-label">{login.t("registration")}</legend>

        <div class="check-set">
          {#each offers as offer (offer)}
            <label class="check">
              <input
                type="radio"
                name="registration"
                value={offer}
                bind:group={registration}
              />
              <span>{login.t(`registration_${offer}`)}</span>
            </label>
          {/each}
        </div>

        {#if registration === "bounded"}
          <input
            type="text"
            name="registration_scopes"
            class="control"
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
            bind:value={scopes}
          />
        {/if}

        <span class="field-hint">{login.t("registration_hint")}</span>
      </fieldset>

      <div class="ledger-row ledger-row-tight">
        <span class="ledger-label">{login.t("mail")}</span>
        <span class="ledger-value"
          >{setup.mails ? login.t("mail_on") : login.t("mail_off")}</span>
      </div>

      <div class="ledger-row ledger-row-tight">
        <span class="ledger-label">{login.t("origin")}</span>
        <span class="ledger-value aside-mono">{origin}</span>
      </div>
    </div>

    <Action
      {login}
      type="submit"
      {ready}
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
