<script>
import { untrack } from "svelte";
import Action from "../shared/Action.svelte";
import SignupHead from "../shared/SignupHead.svelte";

let { login } = $props();

const signup = $derived(login.auth.signup ?? {});
const asks = $derived(signup.asks ?? {});
const firstRun = $derived(Boolean(signup.firstRun));
const docs = $derived(login.auth.docs);
const origin = typeof location === "undefined" ? "" : location.origin;

const held = untrack(() => login.auth.signup ?? {});

let token = $state("");
let nickname = $state(held.nickname ?? "");
let email = $state(held.email ?? "");
let person = $state(held.name ?? "");
let phone = $state(held.phone ?? "");

const filled = (value) => value.trim().length > 0;
const needs = (field, value) => asks[field] !== "required" || filled(value);

const valid = $derived(
  (!signup.token || filled(token)) &&
    needs("nickname", nickname) &&
    needs("email", email) &&
    needs("phone", phone) &&
    (filled(nickname) || filled(email)),
);

function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading) {
    login.submit("signup", { token, nickname, email, name: person, phone });
  }
}
</script>

<div class="setup flow" class:setup-ready={valid}>
  <SignupHead {login} {firstRun} steps={signup.steps} at={1} mark={nickname || email} />

  <form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
    <div class="slab">
      {#if signup.token}
        <label class="ledger-row ledger-step" class:ledger-step-done={filled(token)}>
          <span class="ledger-label">{login.t("token")}</span>
          <input type="password" name="token" class="control" autocomplete="off" bind:value={token} />
          <span class="field-hint">{login.t("token_hint")}</span>
        </label>
      {/if}

      <label class="ledger-row ledger-step" class:ledger-step-done={filled(person)}>
        <span class="ledger-label">{login.t("name")}</span>
        <!-- svelte-ignore a11y_autofocus -->
        <input type="text" name="name" class="control" autocomplete="name" autofocus bind:value={person} />
      </label>

      {#if asks.nickname !== "off"}
        <label class="ledger-row ledger-step" class:ledger-step-done={filled(nickname)}>
          <span class="ledger-label">{login.t("nickname")}</span>
          <input
            type="text"
            name="nickname"
            class="control"
            autocomplete="username"
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
            bind:value={nickname}
          />
        </label>
      {/if}

      {#if asks.email !== "off"}
        <label class="ledger-row ledger-step" class:ledger-step-done={filled(email)}>
          <span class="ledger-label">{login.t("email")}</span>
          <input type="email" name="email" class="control" autocomplete="email" bind:value={email} />
        </label>
      {/if}

      {#if asks.phone !== "off"}
        <label class="ledger-row ledger-step" class:ledger-step-done={filled(phone)}>
          <span class="ledger-label">{login.t("phone")}</span>
          <input
            type="tel"
            name="phone"
            class="control"
            autocomplete="tel"
            placeholder="+15551234567"
            bind:value={phone}
          />
        </label>
      {/if}

      {#if firstRun}
        <div class="ledger-row">
          <span class="ledger-label">{login.t("origin")}</span>
          <span class="ledger-value aside-mono">{origin}</span>
        </div>
      {/if}
    </div>

    <Action
      {login}
      type="submit"
      ready={valid}
      busy={login.loading}
      label={login.t("continue")}
      working={login.t("working")}
    />
  </form>

  {#if firstRun}
    <p class="aside">
      {login.t("once")}
      {#if docs}
        <a class="textlink" href={docs} rel="noopener" target="_blank">{login.t("docs")}</a>
      {/if}
    </p>
  {:else}
    <p class="aside">
      {login.t("have_account")}
      <button type="button" class="textlink" disabled={login.loading} onclick={() => login.startOver()}
        >{login.t("sign_in_instead")}</button
      >
    </p>
  {/if}
</div>
