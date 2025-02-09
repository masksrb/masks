<script>
  import { run } from "svelte/legacy";

  import { DateTime } from "luxon";
  import { onMount, onDestroy } from "svelte";

  let { ...props } = $props();
  let { timestamp, style = "narrow", ago = "ago" } = props;

  let time = $state();
  let intervalId;
  let interval;

  function updateTime(ts) {
    if (ts) {
      time = DateTime.fromISO(ts).toRelative({ style, base: DateTime.now() });
      time = time.replace(/ago$/, ago || "ago");
    }

    interval = time?.includes("sec") ? 1000 : 60 * 1000;
  }

  onMount(() => {
    updateTime(timestamp);

    intervalId = setInterval(() => {
      updateTime(timestamp);
    }, interval);
  });

  onDestroy(() => {
    clearInterval(intervalId);
  });

  updateTime(timestamp);
</script>

<span>{time}</span>
