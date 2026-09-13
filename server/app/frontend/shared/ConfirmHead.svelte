<script>
import Head from "./Head.svelte";
import Identified from "./Identified.svelte";
import SignupHead from "./SignupHead.svelte";

let { login, title, lede = null, tone = null } = $props();

const confirmation = $derived(login.auth.confirmation ?? {});
</script>

{#if confirmation.signingUp}
  <SignupHead
    {login}
    firstRun={false}
    steps={confirmation.steps}
    at={confirmation.steps?.length ?? 3}
    mark={login.actor?.identifier ?? ""}
  />

  <div class="prompt-head">
    <h2 class="prompt-title">{title}</h2>
    {#if lede}<p class="prompt-lede">{lede}</p>{/if}
  </div>
{:else}
  <Head {login} {title} {lede} {tone} />

  <Identified {login} />
{/if}
