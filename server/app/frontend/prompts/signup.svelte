<script>
import { untrack } from "svelte";
import Action from "../shared/Action.svelte";
import Hint from "../shared/Hint.svelte";
import SignupHead from "../shared/SignupHead.svelte";
import { solve } from "../lib/work.js";

let { login } = $props();

const signup = $derived(login.auth.signup ?? {});
const asks = $derived(signup.asks ?? {});
const fixed = $derived(new Set(signup.fixed ?? []));
const firstRun = $derived(Boolean(login.auth.signingUp?.firstRun));
const docs = $derived(login.auth.docs);
const origin = typeof location === "undefined" ? "" : location.origin;

const held = untrack(() => login.auth.signup ?? {});

let token = $state("");
let nickname = $state(held.nickname ?? "");
let email = $state(held.email ?? "");
let name = $state(held.name ?? "");
let phone = $state(held.phone ?? "");
let proving = $state(false);
let picking = $state(Boolean(held.nickname));

const filled = (value) => value.trim().length > 0;
const needs = (field, value) => asks[field] !== "required" || filled(value);

const suggested = $derived(
  email
    .split("@")[0]
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, ""),
);
const nicknameWanted = $derived(asks.nickname !== "off");
const nicknameShown = $derived(
  nicknameWanted &&
    (picking || asks.email === "off" || (login.auth.messages ?? []).some((held) => held.field === "nickname")),
);
const chosenNickname = $derived(nicknameShown ? nickname : nicknameWanted ? suggested : "");

const valid = $derived(
  (!signup.token || filled(token)) &&
    needs("nickname", chosenNickname) &&
    needs("email", email) &&
    needs("phone", phone) &&
    (filled(chosenNickname) || filled(email)),
);

$effect(() => {
  solve(signup.work).catch(() => null);
});

async function proof() {
  proving = true;

  try {
    return (await solve(signup.work)) ?? {};
  } catch {
    return {};
  } finally {
    proving = false;
  }
}

async function onsubmit(event) {
  event.preventDefault();

  if (valid && !login.loading && !proving) {
    const work = await proof();

    login.submit("signup", { token, nickname: chosenNickname, email, name, phone, ...work });
  }
}
</script>

<div class="setup flow" class:setup-ready={valid}>
  <SignupHead {login} at={1} />

  <form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
    <div class="slab">
      {#if signup.token}
        <label class="ledger-row ledger-step" class:ledger-step-done={filled(token)}>
          <span class="ledger-label">{login.t("token")}</span>
          <!-- svelte-ignore a11y_autofocus -->
          <input type="password" name="token" class="control" autocomplete="off" autofocus bind:value={token} />
          <Hint {login} field="token" hint={login.t("token_hint")} />
        </label>
      {/if}

      <label class="ledger-row ledger-step" class:ledger-step-done={filled(name)}>
        <span class="ledger-label">{login.t("name")}</span>
        <!-- svelte-ignore a11y_autofocus -->
        <input type="text" name="name" class="control" autocomplete="name" autofocus={!signup.token} bind:value={name} />
      </label>

      {#if asks.email !== "off"}
        <label class="ledger-row ledger-step" class:ledger-step-done={filled(email)}>
          <span class="ledger-label">{login.t("email")}</span>
          <input
            type="email"
            name="email"
            class="control"
            autocomplete="email"
            readonly={fixed.has("email")}
            bind:value={email}
          />
          <Hint {login} field="email" />
        </label>
      {/if}

      {#if nicknameShown}
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
            placeholder={suggested}
            bind:value={nickname}
          />
          <Hint {login} field="nickname" />
        </label>
      {:else if nicknameWanted}
        <div class="ledger-row">
          <button type="button" class="textlink ledger-link" onclick={() => (picking = true)}>{login.t("pick_nickname")}</button>
          {#if suggested}
            <span class="field-hint">{login.t("nickname_hint", { suggested })}</span>
          {/if}
        </div>
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
          <Hint {login} field="phone" />
        </label>
      {/if}
    </div>

    <Action
      {login}
      type="submit"
      ready={valid}
      busy={login.loading || proving}
      label={login.t("continue")}
      working={proving ? login.t("proving") : login.t("working")}
    />
  </form>

  {#if firstRun}
    <p class="aside">
      {login.t("origin", { origin })}
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
