<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";
import Identified from "../shared/Identified.svelte";
import PasskeyButton from "../shared/PasskeyButton.svelte";
import { available } from "../lib/passkey.js";

let { login } = $props();

let code = $state("");
let remember = $state(false);
let useApp = $state(false);

const methods = $derived(login.auth.secondFactors ?? { otp: true });
const codeFactors = $derived(login.auth.codeFactors ?? {});
const sent = $derived(useApp ? null : login.auth.codeSent);
const valid = $derived(code.replace(/\D/g, "").length === 6);
const passkeyReady = $derived(
  Boolean(methods.passkey && login.auth.passkey?.offered) && available(),
);
const asking = $derived(Boolean(sent) || methods.otp);
const stuck = $derived(
  !asking && !passkeyReady && !login.backupCodes && Object.keys(codeFactors).length === 0,
);
const why = $derived.by(() => {
  if (login.auth.codesWithheld?.includes("email")) return "stuck_inbox";
  if (!methods.passkey) return "stuck_nothing";

  return globalThis.isSecureContext ? "stuck_unsupported" : "stuck_insecure";
});

function submit() {
  if (!valid || login.loading) return;

  const entered = code;
  code = "";

  if (sent) {
    login.submit("code:verify", { code: entered, remember });
  } else {
    login.submit("otp", { code: entered, remember });
  }
}

function onsubmit(event) {
  event.preventDefault();
  submit();
}

function send(factor) {
  useApp = false;
  login.submit("code:send", { factor });
}

$effect(() => {
  if (valid) submit();
});
</script>

{#snippet trust()}
  {#if login.rememberable}
    <label class="check">
      <input type="checkbox" bind:checked={remember} />
      <span>{login.t("trust", { duration: login.auth.trustFor })}</span>
    </label>
  {/if}
{/snippet}

{#if stuck}
  <Head {login} tone="bad" title={login.t("halted")} lede={login.t(why)} />

  <Identified {login} />

  <Action
    {login}
    quiet
    label={login.t("start_over")}
    working={login.t("working")}
    busy={login.loading}
    onclick={() => login.startOver()}
  />
{:else}
  <Head
    {login}
    title={login.t(asking ? "title" : "title_passkey")}
    lede={sent ? login.t("sent_to", { to: sent.to }) : null}
  />

  <Identified {login} />

  {#if asking}
    <form {onsubmit} class="flow" aria-busy={login.loading || undefined}>
      <label class="field">
        <span class="field-label">{login.t("code")}</span>
        <!-- svelte-ignore a11y_autofocus -->
        <input
          type="text"
          name="code"
          class="control control-code"
          inputmode="numeric"
          pattern="[0-9 ]*"
          autocomplete="one-time-code"
          maxlength="7"
          spellcheck="false"
          autofocus
          bind:value={code}
        />
      </label>

      {@render trust()}

      <Action
        {login}
        type="submit"
        ready={valid}
        busy={login.loading}
        label={login.t("continue")}
        working={login.t("checking")}
      />
    </form>
  {/if}

  {#if passkeyReady}
    {#if !asking}
      {@render trust()}
    {/if}

    <PasskeyButton {login} params={{ remember }} />
  {/if}

  {#if !asking && !passkeyReady && Object.keys(codeFactors).length > 0}
    {@render trust()}
  {/if}

  {#each Object.entries(codeFactors) as [factor, to] (factor)}
    {#if sent?.factor === factor}
      {#if sent.resendable}
        <Action {login} plain label={login.t("send_again")} onclick={() => send(factor)} />
      {/if}
    {:else}
      <Action
        {login}
        plain
        label={login.t(`send_${factor}`, { to })}
        onclick={() => send(factor)}
      />
    {/if}
  {/each}

  {#if sent && methods.otp}
    <Action {login} plain label={login.t("use_app")} onclick={() => (useApp = true)} />
  {/if}

  {#if login.backupCodes}
    <Action
      {login}
      plain
      label={login.t("use_backup_code")}
      onclick={() => login.submit("use-backup-code", {})}
    />
  {/if}
{/if}
