<script>
  import _ from "lodash-es";

  import { X, Check, Download, Copy, History } from "lucide-svelte";
  import { base32crockford } from "@scure/base";

  import PasswordInput from "@/components/PasswordInput.svelte";
  import CopyButton from "@/components/CopyButton.svelte";
  import Time from "@/components/Time.svelte";
  import Alert from "@/components/Alert.svelte";
  import Card from "@/components/Card.svelte";

  let { prompt, auth, authorize, authorizing } = $props();

  let generating = $state();
  let generated = $derived(auth?.actor?.savedBackupCodesAt);

  function generateCodes(count = 10, length = 20) {
    const codes = new Set();

    while (codes.size < count) {
      const randomBytes = new Uint8Array(Math.ceil((length * 5) / 8));
      crypto.getRandomValues(randomBytes);

      const code = base32crockford.encode(randomBytes).slice(0, length);
      codes.add(code);
    }

    return Array.from(codes);
  }

  function downloadCodes(codes) {
    const blob = new Blob([codes.join("\n")], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `${[auth?.settings?.name, "codes"].filter(Boolean).join("-")}.txt`;
    link.click();
    URL.revokeObjectURL(url);
  }

  function saveCodes(value) {
    authorize({
      event: prompt.verification("backup-codes:replace", {
        done: () => {
          generating = false;
          codes = generateCodes();
        },
      }),
      updates: { codes: value },
    });
  }

  let codes = $state(generateCodes());
  let enableCta = $derived(auth?.actor?.savedBackupCodesAt ? "save" : "enable");
  let denied = $state();
  let code = $state();

  let verifyCode = () => {
    authorize({
      sudo: true,
      event: "backup-code:verify",
      updates: { backupCode: code },
    }).then((prompt) => {
      if (prompt?.warnings?.length) {
        denied = true;
      }
    });
  };

  let warnEntry = $derived(
    !auth?.actor?.savedBackupCodesAt && auth?.actor?.secondFactors?.length
  );
</script>

{#if authorizing}
  <Alert type="neutral">
    <div class="flex items-center gap-3 mb-1.5">
      <div
        class="flex items-center gap-1.5 p-1 text-xs font-bold bg-base-300 text-base-content px-2 rounded-lg"
      >
        <div class="whitespace-nowrap">
          {#if auth.actor.remainingBackupCodes == 1}
            1 remaining
          {:else}
            {auth?.actor?.remainingBackupCodes} remaining
          {/if}
        </div>
      </div>

      {#if denied}
        <span class="text-xs text-error"> Invalid code. try again... </span>
      {:else}
        <div
          class="text-xs whitespace-nowrap flex items-center gap-1.5 opacity-75 hidden md:block"
        >
          <span>
            Your codes were generated <Time
              timestamp={auth.actor.savedBackupCodesAt}
            />.
          </span>
        </div>
      {/if}
    </div>

    <div class="flex items-center gap-3 w-full mb-1.5">
      <PasswordInput
        inputClass="w-full grow"
        class={[
          "input-neutral input-lg input-ghost w-full",
          denied ? "animate-denied input-error" : "",
        ].join(" ")}
        placeholder={`Enter a backup code...`}
        bind:value={code}
      >
        {#snippet end()}
          <button
            class="btn btn-sm px-1.5 btn-success -mr-1.5"
            disabled={!code || denied}
            onclick={verifyCode}
          >
            {#if denied}
              <X />
            {:else}
              <Check />
            {/if}
          </button>
        {/snippet}
      </PasswordInput>
    </div>
  </Alert>
{:else}
  <Card>
    <div class="flex items-center gap-1.5 py-1">
      <History size="14" />
      <div class="label-bold">Backup codes</div>
    </div>
    <div class="flex items-end gap-3 mb-3">
      <div class="grow opacity-75 text-sm">
        {#if generating}
          Keep the following backup codes in a safe place, then press <b
            >{enableCta}</b
          >. {#if auth?.actor?.savedBackupCodesAt}
            Your old backup codes will no longer work.
          {/if}
        {:else if generated}
          {#key auth.actor.savedBackupCodesAt}
            <div>
              <p class="dark:text-white text-black mb-0.5">
                {auth?.actor?.remainingBackupCodes} remaining backup codes
              </p>
              <p class="text-xs">
                generated <Time
                  style="long"
                  timestamp={auth?.actor?.savedBackupCodesAt}
                />
              </p>
            </div>
          {/key}
        {:else}
          Generate backup codes for times when you lose access to other
          secondary credentials.

          {#if warnEntry}
            <span class="text-warning">Backup codes are <b>required</b>.</span>
          {/if}
        {/if}
      </div>

      {#if generating}
        <div class="flex flex-col items-center">
          <button
            disabled={!generating}
            class="btn btn-sm btn-success"
            type="button"
            onclick={() => saveCodes(codes)}
          >
            {enableCta}
          </button>
          {#if auth?.actor?.savedBackupCodesAt}
            <button
              class="btn btn-sm btn-link whitepsace-nowrap !btn-neutral flex items-center gap-0"
              type="button"
              onclick={() => (generating = false)}>cancel</button
            >
          {/if}
        </div>
      {:else if generated}
        <button
          class="btn btn-xs"
          type="button"
          onclick={() => (generating = true)}>generate new codes</button
        >
      {/if}
    </div>

    {#if generating}
      <div class="p-3 bg-base-100 rounded-lg shadow-inner mb-3">
        <div class="flex gap-3 items-center mb-3">
          <button
            class="btn btn-sm grow"
            type="button"
            onclick={() => downloadCodes(codes)}
            ><Download size="14" /> Download</button
          >
          <CopyButton class="btn btn-sm grow" value={codes}>
            {#snippet after({ copied })}
              {copied ? "Copied!" : "Copy"}
            {/snippet}
          </CopyButton>
        </div>

        <div class="overflow-auto">
          <pre
            class="leading-loose tracking-widest font-mono text-center">{codes.join(
              "\n"
            )}</pre>
        </div>
      </div>
    {:else if !generated}
      <button
        class={`btn btn-sm w-full mb-3 ${warnEntry ? "btn-warning" : ""}`}
        type="button"
        onclick={() => (generating = true)}>Generate backup codes</button
      >
    {/if}
  </Card>
{/if}
