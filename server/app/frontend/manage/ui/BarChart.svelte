<script>
  let { points, label, unit = "sign-ins" } = $props();

  const W = 720;
  const H = 168;
  const FOOT = 22;
  const PLOT = H - FOOT;
  const GAP = 2;
  const CAP = 4;

  const peak = $derived(Math.max(1, ...points.map((point) => point.value)));
  const step = $derived(W / Math.max(points.length, 1));
  const width = $derived(Math.max(step - GAP, 1));
  const total = $derived(points.reduce((sum, point) => sum + point.value, 0));

  let hovered = $state(null);

  function bar(value, x) {
    const height = value === 0 ? 2 : Math.max((value / peak) * (PLOT - 8), 3);
    const y = PLOT - height;
    const radius = Math.min(CAP, width / 2, height);

    return [
      `M ${x} ${PLOT}`,
      `L ${x} ${y + radius}`,
      `Q ${x} ${y} ${x + radius} ${y}`,
      `L ${x + width - radius} ${y}`,
      `Q ${x + width} ${y} ${x + width} ${y + radius}`,
      `L ${x + width} ${PLOT}`,
      "Z",
    ].join(" ");
  }

  const ticks = $derived(
    points.length
      ? [0, Math.floor((points.length - 1) / 2), points.length - 1]
          .filter((at, index, all) => all.indexOf(at) === index)
          .map((at) => ({ at, point: points[at] }))
      : [],
  );
</script>

<figure class="chart">
  <figcaption class="chart-head">
    <span class="chart-label">{label}</span>
    <span class="chart-peak">{peak} on the busiest day</span>
  </figcaption>

  <div class="chart-plot">
    <svg
      viewBox="0 0 {W} {H}"
      class="chart-svg"
      role="img"
      aria-label="{label}: {total} {unit} across {points.length} days, peaking at {peak}."
    >
      <line class="chart-base" x1="0" y1={PLOT} x2={W} y2={PLOT} />

      {#each points as point, index (point.key)}
        <path
          class="chart-bar"
          class:chart-bar-idle={point.value === 0}
          class:chart-bar-on={hovered?.index === index}
          d={bar(point.value, index * step)}
        />
      {/each}

      {#each points as point, index (point.key)}
        <rect
          class="chart-hit"
          x={index * step}
          y="0"
          width={step}
          height={PLOT}
          onmouseenter={() => (hovered = { ...point, index })}
          onmouseleave={() => (hovered = null)}
          onfocus={() => (hovered = { ...point, index })}
          onblur={() => (hovered = null)}
          tabindex="-1"
          role="presentation"
        />
      {/each}
    </svg>

    {#if hovered}
      <div
        class="chart-tip"
        style="left: {((hovered.index + 0.5) / points.length) * 100}%"
        aria-hidden="true"
      >
        <strong>{hovered.value}</strong>
        {hovered.value === 1 ? unit.replace(/s$/, "") : unit}
        <span>{hovered.label}</span>
      </div>
    {/if}
  </div>

  <div class="chart-axis">
    {#each ticks as tick (tick.at)}
      <span style="left: {((tick.at + 0.5) / points.length) * 100}%">{tick.point.label}</span>
    {/each}
  </div>

  <table class="sr-only">
    <caption>{label}</caption>
    <thead><tr><th>Day</th><th>{unit}</th></tr></thead>
    <tbody>
      {#each points as point (point.key)}
        <tr><td>{point.label}</td><td>{point.value}</td></tr>
      {/each}
    </tbody>
  </table>
</figure>
