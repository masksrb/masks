<script>
let { login, title, lede = null, cap = null, tone = null, busy = false } =
  $props();

const running = $derived(tone === null && (busy || login.loading));
</script>

<div class="prompt-head">
  {#if cap}
    <span class="record-cap">{cap}</span>
  {/if}

  <h1 class="prompt-title">{title}</h1>

  {#if lede}
    <p class="prompt-lede">{lede}</p>
  {/if}

  <span
    class="pulse"
    class:pulse-on={running}
    class:pulse-done={tone === "done"}
    class:pulse-bad={tone === "bad"}
    aria-hidden="true"
  ></span>
</div>
