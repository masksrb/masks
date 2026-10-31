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
const signingUp = $derived(Boolean(login.auth.signingUp));
const offers = $derived(enrolment.offers ?? { otp: true, passkey: true, backupCodes: true });
const secured = $derived(!enrolment.required);
const issued = $derived(codes.issued ?? []);
const sendable = $derived(Object.entries(enrolment.codes ?? {}));
const passkeyable = $derived(offers.passkey && available());

const ways = $derived(
  [
    offers.otp && !otp.enabled && ["otp", login.t("otp"), login.t("otp_about")],
    passkeyable && !passkeys.verified && ["passkey", login.t("passkey"), login.t("passkey_about")],
    ...sendable
      .filter(([, row]) => !row.enabled)
      .map(([factor, row]) => [factor, login.t(`codes_${factor}`), login.t(`codes_${factor}_about`, { to: row.to })]),
  ].filter(Boolean),
);

const on = $derived(
  [
    otp.enabled && login.t("otp"),
    passkeys.count > 0 && login.t("passkeys_some", { count: passkeys.count }),
    ...sendable.filter(([, row]) => row.enabled).map(([factor]) => login.t(`codes_${factor}`)),
  ].filter(Boolean),
);

let picked = $state(null);
let entered = $state({ "enrol:otp": "", "enrol:code": "" });
let kept = $state(false);
let copied = $state(false);

const anything = $derived(on.length > 0);
const choosing = $derived(picked === null || !ways.some(([key]) => key === picked));
const sentFactor = $derived(sendable.find(([, row]) => row.sent)?.[0] ?? null);
const showing = $derived(choosing ? (sentFactor ?? null) : picked);
const ready = $derived(secured && (issued.length === 0 || kept));
const title = $derived(anything ? login.t("on_title") : login.t("title"));
const lede = $derived(anything ? login.t("on_lede") : enrolment.required ? login.t("lede") : login.t("lede_optional"));

const complete = (name) => entered[name].replace(/\D/g, "").length === 6;

function turnOn(submitted, name) {
  submitted.preventDefault();

  if (!complete(name) || login.loading) return;

  const code = entered[name];
  entered[name] = "";

  login.submit(name, { code }).then(() => {
    picked = null;
  });
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

{#snippet codeForm(name)}
  <form class="flow-tight" onsubmit={(submitted) => turnOn(submitted, name)} aria-busy={login.loading || undefined}>
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
      bind:value={entered[name]}
    />

    <Action {login} type="submit" quiet ready={complete(name)} label={login.t("turn_on")} />
  </form>
{/snippet}

{#snippet otherWay()}
  {#if ways.length > 1 || anything}
    <button type="button" class="textlink ledger-link" onclick={() => (picked = null)}>{login.t("another_way")}</button>
  {/if}
{/snippet}

<div class="flow" class:setup={signingUp} class:setup-ready={signingUp && ready}>
  {#if signingUp}
    <SignupHead {login} at={2} />

    <p class="aside">{lede}</p>
  {:else}
    <Head {login} {title} {lede} />

    <Identified {login} />
  {/if}

  {#if anything && showing === null}
    <div class="slab">
      <div class="ledger-row">
        <span class="ledger-label">{login.t("on_label")}</span>
        <ul class="plain-list">
          {#each on as way (way)}
            <li>{way}</li>
          {/each}
        </ul>
      </div>

      {#if offers.backupCodes}
        <div class="ledger-row">
          <span class="ledger-label">{login.t("backup_codes")}</span>

          {#if issued.length > 0}
            <ol class="codes">
              {#each issued as held (held)}
                <li>{held}</li>
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
          {/if}
        </div>
      {/if}

      {#if ways.length}
        <div class="ledger-row">
          <button type="button" class="textlink ledger-link" onclick={() => (picked = ways[0][0])}>{login.t("add_way")}</button>
        </div>
      {/if}
    </div>
  {:else if showing === null}
    <ul class="ways">
      {#each ways as [key, name, about] (key)}
        <li>
          <button type="button" class="way" onclick={() => (picked = key)}>
            <span class="way-title">{name}</span>
            <span class="way-about">{about}</span>
          </button>
        </li>
      {/each}
    </ul>
  {:else if showing === "otp"}
    <div class="slab">
      <div class="ledger-row">
        <span class="ledger-label">{login.t("otp")}</span>
        <div class="enrol">
          <a class="enrol-qr" href={otp.uri} aria-label={login.t("open")}>{@html otp.qr}</a>
          <div class="enrol-key">
            <span class="field-hint">{login.t("scan_hint")}</span>
            <span class="enrol-secret">{otp.secret}</span>
          </div>
        </div>

        {@render codeForm("enrol:otp")}
      </div>

      <div class="ledger-row">{@render otherWay()}</div>
    </div>
  {:else if showing === "passkey"}
    <div class="slab">
      <div class="ledger-row">
        <span class="ledger-label">{login.t("passkeys")}</span>
        <span class="field-hint">{login.t("passkey_about")}</span>

        <PasskeyButton
          {login}
          enrolling
          label={passkeys.count > 0 ? login.t("add_another_passkey") : login.t("add_passkey")}
        />
      </div>

      <div class="ledger-row">{@render otherWay()}</div>
    </div>
  {:else}
    {@const row = enrolment.codes?.[showing] ?? {}}
    <div class="slab">
      <div class="ledger-row">
        <span class="ledger-label">{login.t(`codes_${showing}`)}</span>

        {#if row.sent}
          <span class="field-hint">{login.t("sent_to", { to: row.to })}</span>

          {@render codeForm("enrol:code")}
        {:else}
          <span class="field-hint">{login.t(`codes_${showing}_about`, { to: row.to })}</span>

          <Action
            {login}
            quiet
            label={login.t("send_code")}
            onclick={() => login.submit("enrol:code-send", { factor: showing })}
          />
        {/if}
      </div>

      <div class="ledger-row">{@render otherWay()}</div>
    </div>
  {/if}

  <form class="flow" onsubmit={done}>
    {#if issued.length > 0}
      <label class="check">
        <input type="checkbox" name="kept" required bind:checked={kept} />
        <span>{login.t("kept")}</span>
      </label>
    {/if}

    {#if anything || !enrolment.required}
      <Action
        {login}
        type="submit"
        {ready}
        busy={login.loading}
        label={anything || enrolment.required ? login.t("done") : login.t("skip")}
        working={login.t("working")}
      />
    {/if}
  </form>
</div>
