<script>
import Action from "../shared/Action.svelte";
import Head from "../shared/Head.svelte";
import Identified from "../shared/Identified.svelte";
import SignupHead from "../shared/SignupHead.svelte";
import PasskeyButton from "../shared/PasskeyButton.svelte";
import { available } from "../lib/passkey.js";

let { login } = $props();

const enrolment = $derived(login.auth.enrolment ?? {});
const otp = $derived(enrolment.otp ?? {});
const passkeys = $derived(enrolment.passkeys ?? { count: 0 });
const codes = $derived(enrolment.backupCodes ?? {});
const signingUp = $derived(Boolean(login.auth.journey));
const offers = $derived(enrolment.offers ?? { otp: true, passkey: true, backupCodes: true });
const secured = $derived(!enrolment.required);
const issued = $derived(codes.issued ?? []);

const passkeyable = $derived(offers.passkey && available());

let code = $state("");
let kept = $state(false);
let copied = $state(false);

const coded = $derived(code.replace(/\D/g, "").length === 6);
const ready = $derived(secured && (issued.length === 0 || kept));
const anything = $derived(Boolean(otp.enabled || passkeys.count > 0));
const lede = $derived(enrolment.required ? login.t("lede") : login.t("lede_optional"));

function turnOn(event) {
  event.preventDefault();

  if (!coded || login.loading) return;

  const entered = code;
  code = "";

  login.submit("enrol:otp", { code: entered });
}

const origin = typeof location === "undefined" ? "" : location.origin;
const host = typeof location === "undefined" ? "masks" : location.hostname;

const saved = $derived.by(() => {
  const lines = [
    login.t("backup_codes_file", { account: login.actor?.identifier ?? "", origin }),
    login.t("backup_codes_hint"),
    "",
    ...issued,
    "",
  ];

  return `data:text/plain;charset=utf-8,${encodeURIComponent(lines.join("\n"))}`;
});

async function copy() {
  try {
    await navigator.clipboard.writeText(issued.join("\n"));
    copied = true;
  } catch {
    copied = false;
  }
}

function done(event) {
  event.preventDefault();

  if (ready && !login.loading) login.submit("enrol:done", { kept });
}
</script>

<div class="flow" class:setup={signingUp} class:setup-ready={signingUp && ready}>
  {#if signingUp}
    <SignupHead {login} at={2} mark={login.actor?.identifier ?? ""} />

    <p class="aside">{lede}</p>
  {:else}
    <Head
      {login}
      title={login.t("title")}
      {lede}
    />

    <Identified {login} />
  {/if}

  <div class="slab">
    {#if offers.otp}
    <div class="ledger-row ledger-step" class:ledger-step-done={otp.enabled}>
      <span class="ledger-label">{login.t("otp")}</span>

      {#if otp.enabled}
        <span class="ledger-value">{login.t("otp_on")}</span>
      {:else}
        <div class="enrol">
          <a class="enrol-qr" href={otp.uri} aria-label={login.t("open")}>{@html otp.qr}</a>
          <div class="enrol-key">
            <span class="field-hint">{login.t("scan_hint")}</span>
            <span class="aside-mono enrol-secret">{otp.secret}</span>
          </div>
        </div>

        <form class="flow-tight" onsubmit={turnOn} aria-busy={login.loading || undefined}>
          <input
            type="text"
            name="code"
            class="control control-code"
            inputmode="numeric"
            pattern="[0-9 ]*"
            autocomplete="one-time-code"
            maxlength="7"
            spellcheck="false"
            aria-label={login.t("code")}
            placeholder={login.t("code")}
            bind:value={code}
          />

          <Action {login} type="submit" quiet ready={coded} label={login.t("turn_on")} />
        </form>
      {/if}
    </div>
    {/if}

    {#if passkeyable}
      <div class="ledger-row ledger-step" class:ledger-step-done={passkeys.verified}>
        <span class="ledger-label">{login.t("passkeys")}</span>
        <span class="field-hint">
          {passkeys.count > 0
            ? login.t("passkeys_some", { count: passkeys.count })
            : login.t("passkeys_none")}
        </span>

        <PasskeyButton
          {login}
          enrolling
          label={passkeys.count > 0 ? login.t("add_another_passkey") : login.t("add_passkey")}
        />
      </div>
    {/if}

    {#if offers.backupCodes}
    <div class="ledger-row ledger-step" class:ledger-step-done={issued.length > 0 || codes.remaining > 0}>
      <span class="ledger-label">{login.t("backup_codes")}</span>

      {#if issued.length > 0}
        <ol class="codes">
          {#each issued as held (held)}
            <li class="aside-mono">{held}</li>
          {/each}
        </ol>
        <span class="field-hint">{login.t("backup_codes_hint")}</span>
        <div class="codes-actions">
          <button type="button" class="textlink" onclick={copy}>
            {copied ? login.t("copied") : login.t("copy")}
          </button>
          <a class="textlink" href={saved} download="backup-codes-{host}.txt">{login.t("download")}</a>
        </div>
      {:else if codes.remaining > 0}
        <span class="field-hint">{login.t("backup_codes_left", { count: codes.remaining })}</span>
      {:else}
        <span class="field-hint">{login.t("backup_codes_waiting")}</span>
      {/if}
    </div>
    {/if}
  </div>

  <form class="flow" onsubmit={done}>
    {#if issued.length > 0}
      <label class="check">
        <input type="checkbox" name="kept" required bind:checked={kept} />
        <span>{login.t("kept")}</span>
      </label>
    {/if}

    <Action
      {login}
      type="submit"
      {ready}
      busy={login.loading}
      label={anything || enrolment.required ? login.t("done") : login.t("skip")}
      working={login.t("working")}
    />
  </form>
</div>
